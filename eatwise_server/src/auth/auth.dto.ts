import { IsIn, IsNotEmpty, IsOptional, IsString, Length, Matches } from 'class-validator';

export class SendSmsDto {
  @Matches(/^\+[1-9]\d{6,14}$/, { message: 'phone must be E.164' })
  phone: string;

  @IsIn(['login'])
  scene: string;
}

export class DeviceDto {
  @IsString()
  @IsNotEmpty()
  deviceId: string;

  @IsIn(['ios', 'android'])
  platform: string;

  @IsOptional()
  @IsString()
  osVersion?: string;

  @IsOptional()
  @IsString()
  appVersion?: string;
}

export class PhoneLoginDto {
  @Matches(/^\+[1-9]\d{6,14}$/, { message: 'phone must be E.164' })
  phone: string;

  @IsString()
  @IsNotEmpty()
  code: string;

  @IsOptional()
  device?: DeviceDto;
}

export class RefreshDto {
  @IsString()
  @IsNotEmpty()
  refreshToken: string;
}

/** 用户名策略（D-13 修订）：3-20 位字母/数字/下划线 */
export const USERNAME_PATTERN = /^[a-zA-Z0-9_]{3,20}$/;
/** 密码策略：8-64 位且同时包含字母和数字（前瞻断言组合校验） */
export const PASSWORD_PATTERN = /^(?=.*[A-Za-z])(?=.*\d).{8,64}$/;

export class RegisterDto {
  @Matches(USERNAME_PATTERN, {
    message: 'username must be 3-20 chars of letters, digits or underscore',
  })
  username: string;

  /** DTO 层仅做长度防御；强度（字母+数字）的最终判定在 service → AUTH_PASSWORD_TOO_WEAK */
  @Length(8, 64)
  password: string;

  @IsOptional()
  device?: DeviceDto;
}

export class LoginDto {
  @IsString()
  @IsNotEmpty()
  username: string;

  @IsString()
  @IsNotEmpty()
  password: string;

  @IsOptional()
  device?: DeviceDto;
}

export class ChangePasswordDto {
  @IsString()
  @IsNotEmpty()
  oldPassword: string;

  /** 同注册密码策略：长度防御在 DTO，强度判定在 service */
  @Length(8, 64)
  newPassword: string;
}

export class LogoutDto {
  @IsOptional()
  @IsString()
  deviceId?: string;
}
