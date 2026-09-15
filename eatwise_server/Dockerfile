# syntax=docker/dockerfile:1
# EatWise 服务端生产镜像（云主机自部署用，见 docs/tech/部署-云主机自部署-v1.0.md）。
# 两阶段：build 阶段含 devDependencies（prisma CLI / ts-node，供迁移与灌库）；
# runtime 阶段只留生产依赖 + dist，镜像最小化。

FROM node:20-alpine AS build
WORKDIR /app
# Prisma 引擎按 libssl 探测 openssl 版本：alpine 默认无 openssl，会错误回退
# 1.1.x 引擎并在运行时缺 libssl.so.1.1 崩溃；两个阶段都必须先装。
RUN apk add --no-cache openssl
# 先拷依赖清单与 prisma schema：postinstall 会跑 prisma generate，schema 必须在场。
COPY package.json package-lock.json ./
COPY prisma ./prisma
RUN npm ci
COPY . .
RUN npx prisma generate && npm run build

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apk add --no-cache openssl
COPY package.json package-lock.json ./
COPY prisma ./prisma
# 仅生产依赖；@prisma/client 的 postinstall 需要 schema 生成 client。
RUN npm ci --omit=dev && npx prisma generate && npm cache clean --force
COPY --from=build /app/dist ./dist
EXPOSE 3000
# 启动命令固定 node dist/main.js；环境变量全部经 compose env_file 注入。
CMD ["node", "dist/main.js"]
