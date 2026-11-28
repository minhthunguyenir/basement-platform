import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaModule } from './prisma/prisma.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { BooksModule } from './books/books.module';

@Module({
  imports: [PrismaModule, AuthModule, HealthModule, BooksModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}