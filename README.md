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

| 容器路径 | 用途 | 类型 |
|---|---|---|
| `/data` | DSH 状态：profiles、已装插件、凭据、会话 | named volume `dsh_data` |
| `/workspace` | 你的项目文件（DSH 的工作区根目录） | bind `./workspace` |

`/data` 用 named volume 是因为它是应用状态、不是代码；`docker compose down` 不会删，`down -v` 才会。

## 重启语义

| 操作 | 容器 | DSH 数据 |
|---|---|---|
| `docker compose exec dsh s6-svc -r /run/service/dsh`（只重启进程） | 保持运行 | 保留 |
| DSH 进程崩溃 | 不退出，s6 自动重启进程 | 保留 |
| `docker compose restart dsh` | 重启容器 | 保留 |
| `docker compose down` / `down -v` | 停止并移除 | 保留 / **删除** |

## 安装插件

镜像只装了 DSH 本体，插件按需装进 `web` profile：

```bash
docker compose exec dsh dsh plugin --profile web add -w --save-exact @xmanrui/dsh-im@5.9.1
docker compose exec dsh s6-svc -r /run/service/dsh
```

（`dah-im` 的实际包名是 `@xmanrui/dsh-im`。）插件和凭据都在 `/data` 卷里，重建容器不会丢。

## 发布到 GHCR

[`.github/workflows/publish.yml`](.github/workflows/publish.yml) 构建 `linux/amd64` + `linux/arm64` 并推送到 GitHub Container Registry。

推送到 `main`、推送 `v*.*.*` 标签、或手动触发 `workflow_dispatch`（可指定 `dsh_version`）：

```bash
git tag v0.2.1-rc.2 && git push origin v0.2.1-rc.2
```

镜像地址 `ghcr.io/bitxeno/dsh-docker`，只发布到这里（不推送 Docker Hub）。DSH 版本由 `DSH_VERSION` 构建参数固定，与 Dockerfile 的 `ARG` 默认值一致。

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
