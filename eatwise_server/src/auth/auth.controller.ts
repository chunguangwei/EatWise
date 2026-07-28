import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { CurrentUser, AuthUser } from './current-user.decorator';
import { LogoutDto, PhoneLoginDto, RefreshDto, SendSmsDto } from './auth.dto';
import { AuthService } from './auth.service';
import { Public } from './public.decorator';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  /** A1 发送手机验证码 */
  @Public()
  @Post('sms/send')
  @HttpCode(200)
  sendSms(@Body() dto: SendSmsDto) {
    return this.auth.sendSms(dto.phone, dto.scene);
  }

  /** A2 手机号+验证码登录（无账号则注册） */
  @Public()
  @Post('login/phone')
  @HttpCode(200)
  loginPhone(@Body() dto: PhoneLoginDto) {
    return this.auth.loginPhone(dto.phone, dto.code, dto.device);
  }

  /** A5 刷新令牌（refreshToken 滑动轮换） */
  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  /** A6 注销当前设备会话（幂等） */
  @Post('logout')
  @HttpCode(200)
  logout(@CurrentUser() user: AuthUser, @Body() dto: LogoutDto) {
    return this.auth.logout(user.userId, dto.deviceId);
  }
}
