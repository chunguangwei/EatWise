-- U5 账号删除：帖子匿名化留存需要 userId 可空（物理删用户行不再违反 FK）。
ALTER TABLE "posts" ALTER COLUMN "userId" DROP NOT NULL;
