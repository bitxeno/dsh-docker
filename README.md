# dsh-docker

基于官方 [`deepseek-ai/deepseek-harness`](https://github.com/deepseek-ai/deepseek-harness) 的 Docker 运行环境，结构参考同级的 `../aiclaw-docker`。

镜像用 [s6-overlay](https://github.com/just-containers/s6-overlay) 作为 PID 1，`services.d/dsh/run` 由 s6 监督。因此 **DSH 进程退出或崩溃时，s6 只重启这个进程，容器本身不退出**，数据卷和挂载的 workspace 都保留。

镜像里**没有任何 Docker API 访问**：没装 Docker CLI，也不挂 `docker.sock`。

## 启动

镜像已发布到 GHCR，直接拉取运行，无需本地构建：

```bash
cp .env.example .env      # 可选：填 DEEPSEEK_API_KEY
mkdir -p workspace
docker compose up -d
docker compose logs -f dsh
```

访问 <http://127.0.0.1:3080>。模型/凭据也可以直接在 Web UI 里配置。

要自己改镜像重新构建：

```bash
docker build -t ghcr.io/bitxeno/dsh-docker:latest .
docker compose up -d
```

## 挂载说明

| 容器路径 | 用途 | 宿主机位置 |
|---|---|---|
| `/data/dsh` | DSH_HOME：profiles、已装插件、凭据、会话 | `./data` |
| `/workspace` | 你的项目文件（DSH 的工作区根目录） | `./workspace` |

`DSH_HOME=/data/dsh`，而 `/data` 下没有其他内容，所以直接把 `./data` 挂到 `/data/dsh`，本地目录就是 DSH_HOME 本身，没有多余的嵌套层级。内容示例：

- `./data/profiles/web/` —— profile 与已安装插件（`package.json`、`cordis.patch.yml`、`node_modules`）
- `./data/.credentials.yaml` —— 模型凭据
- `./data/sessions/`、`./data/storages/` —— 会话与状态
- `./data/logs/` —— 启动诊断日志

两个挂载都是 bind，直接对应本地目录，可以直接备份、迁移或用编辑器查看。注意 `./data` 里有凭据，已在 `.gitignore` 中排除，不要提交。

## 局域网 / 反向代理访问

DSH 有一道 **Host/Origin 校验**，每个 `/api` 请求都要先过它，且**在鉴权之前**执行。它只接受三种 Host：

1. loopback（`127.0.0.1` / `localhost`）
2. 容器内监听器绑定的那个 IP
3. `trustedHosts` 里显式列出的 authority

所以用别的机器的 `http://<宿主机IP>:3080` 或域名访问时，必须把该 authority 加进 `DSH_TRUSTED_HOSTS`，否则页面能打开但所有接口返回 **403**（WebSocket 也连不上）。

```dotenv
# .env：写你在浏览器地址栏里实际输入的主机（可带端口），多个用逗号分隔
DSH_TRUSTED_HOSTS=192.168.1.1,dsh.example.com
```

支持 `host` 或 `host:port`；不带端口表示任意端口。改完需要重启容器：

```bash
docker compose up -d
```

客户端和服务端需在同一网段、宿主机防火墙放行 3080。DSH 默认 cookie 不是 `Secure`（明文 HTTP），跨网络暴露时建议加 TLS 反代。

## 重启语义

容器名固定为 `dsh-docker`。操作时用服务名 `dsh` 或容器名都可以：

```bash
docker compose exec dsh ...        # 用服务名
docker exec -it dsh-docker sh      # 用容器名
```

| 操作 | 容器 | DSH 数据 |
|---|---|---|
| `docker compose exec dsh s6-svc -r /run/service/dsh`（只重启进程） | 保持运行 | 保留 |
| DSH 进程崩溃 | 不退出，s6 自动重启进程 | 保留 |
| `docker compose restart dsh` | 重启容器 | 保留 |
| `docker compose down` / `down -v` | 停止并移除 | 保留（数据在本地 `./data`，`-v` 也不再影响） |

## 安装插件

镜像只装了 DSH 本体，插件按需装进 `web` profile：

```bash
docker compose exec dsh dsh plugin --profile web add -w --save-exact @xmanrui/dsh-im@5.9.1
docker compose exec dsh s6-svc -r /run/service/dsh
```

（`dah-im` 的实际包名是 `@xmanrui/dsh-im`。）插件和凭据都在本地 `./data` 里，重建容器不会丢。

## 发布到 GHCR

[`.github/workflows/publish.yml`](.github/workflows/publish.yml) 构建 `linux/amd64` 镜像并推送到 GitHub Container Registry。

推送到 `main`、推送 `v*.*.*` 标签、或手动触发 `workflow_dispatch` 都会构建。

镜像地址 `ghcr.io/bitxeno/dsh-docker`，只发布到这里（不推送 Docker Hub）。

**DSH 版本默认跟随 npm 的 `latest` dist-tag**：Dockerfile 的 `ARG DSH_VERSION=latest` 与工作流的 `DEFAULT_DSH_VERSION` 都是 `latest`，因此 `main` 分支构建出的 `:latest` 镜像每次都会安装当前最新发布的 DSH。要给某个版本打固定镜像，手动触发 `workflow_dispatch` 时把 `dsh_version` 填成精确版本号（如 `0.2.1-rc.5`），或本地构建时覆盖构建参数：

```bash
docker build --build-arg DSH_VERSION=0.2.1-rc.5 -t ghcr.io/bitxeno/dsh-docker:0.2.1-rc.5 .
```

推送 `v*.*.*` 标签是镜像本身的版本号，与内部 DSH 版本无关，无需一致。

发布后需要在仓库的 **Packages** 设置里把该 package 可见性改为 public，否则 `docker compose up` 拉取会 401。

## 目录

- `docker-compose.yml` —— 服务、端口、两个挂载
- `Dockerfile` —— Node 24、s6-overlay、DSH CLI
- `services.d/dsh/run` —— s6 监督的 DSH Web 服务
- `.github/workflows/publish.yml` —— 构建并发布到 GHCR

## 参考

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness#run)
- [s6-overlay](https://github.com/just-containers/s6-overlay)
- [DSH 插件管理](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/reference/README.md#plugin-management)
