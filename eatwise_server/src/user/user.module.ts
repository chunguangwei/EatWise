import { Module } from '@nestjs/common';
import { DeletionScheduler } from './deletion.scheduler';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  controllers: [UserController],
  providers: [UserService, DeletionScheduler],
  exports: [UserService],
})
export class UserModule {}
