import { IsIn, IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';

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

export class LogoutDto {
  @IsOptional()
  @IsString()
  deviceId?: string;
}
