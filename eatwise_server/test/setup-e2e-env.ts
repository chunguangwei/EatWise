// e2e 套件共享环境：supertest 全部走 loopback，同一 IP 会共享全局限流桶。
// 放大 THROTTLE_LIMIT（守卫本身逻辑由各 spec 的 429 断言覆盖，见 throttler spec）。
process.env.THROTTLE_LIMIT = process.env.THROTTLE_LIMIT ?? '100000';
