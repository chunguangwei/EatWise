-- 管理员账号（管理控制台登录体系：账号 + 角色 admin/reviewer，与用户体系完全独立）。
-- 种子由服务端启动时按 env ADMIN_USERNAME/ADMIN_PASSWORD 创建（见 admin-auth.service.ts）。
CREATE TABLE "admin_users" (
    "id" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'reviewer',
    "disabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_users_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "admin_users_username_key" ON "admin_users"("username");
