import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors();

  // Cấu hình Swagger Documentation
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Basement Platform API')
    .setDescription('Tài liệu đặc tả API cho hệ sinh thái Basement Platform (Monorepo)')
    .setVersion('1.0')
    .addTag('health', 'Endpoints kiểm tra sức khỏe hệ thống, kết nối cơ sở dữ liệu và Row-Level Security')
    .build();

  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  const port = process.env.PORT ?? 3001;
  await app.listen(process.env.PORT ?? 3001);
  console.log(`Application is running on: http://localhost:${port}`);
  console.log(`Swagger documentation available at: http://localhost:${port}/api/docs`);
}
void bootstrap();
