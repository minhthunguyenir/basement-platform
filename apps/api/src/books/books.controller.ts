import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CurrentUser } from '@nestjs/authentication';
import {
  ApiBearerAuth,
  ApiBody,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import type { z } from 'zod';
import type { AuthUser } from '../auth/auth.types';
import { BooksService } from './books.service';
import {
  createBookCopySchema,
  createBookSchema,
  listBooksQuerySchema,
  updateBookCopySchema,
  updateBookSchema,
} from './books.schemas';

function parseZod<S extends z.ZodTypeAny>(schema: S, input: unknown): z.output<S> {
  const result = schema.safeParse(input);
  if (!result.success) {
    throw new BadRequestException({
      message: 'Dữ liệu đầu vào không hợp lệ',
      errors: result.error.flatten().fieldErrors,
    });
  }
  return result.data;
}

@ApiTags('books')
@ApiBearerAuth()
@Controller('books')
export class BooksController {
  constructor(private readonly booksService: BooksService) {}

  @Get()
  @ApiOperation({ summary: 'Tìm kiếm & lọc danh mục đầu sách kèm tồn kho theo chi nhánh' })
  @ApiQuery({ name: 'q', required: false, description: 'Từ khóa tên sách, tác giả, ISBN, mô tả' })
  @ApiQuery({ name: 'category', required: false })
  @ApiQuery({ name: 'language', required: false, enum: ['vi', 'en'] })
  @ApiQuery({ name: 'branchId', required: false })
  @ApiQuery({ name: 'availableOnly', required: false, enum: ['true', 'false'] })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 20 })
  findAll(@CurrentUser() user: AuthUser, @Query() rawQuery: Record<string, unknown>) {
    const query = parseZod(listBooksQuerySchema, rawQuery);
    return this.booksService.findAll(user, query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Xem chi tiết đầu sách và danh sách bản sao tại các chi nhánh' })
  findOne(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.booksService.findOne(user, id);
  }

  @Post()
  @ApiOperation({ summary: 'Thêm đầu sách mới vào danh mục chuỗi' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['title', 'author'],
      properties: {
        title: { type: 'string', example: 'Clean Architecture' },
        author: { type: 'string', example: 'Robert C. Martin' },
        category: { type: 'string', example: 'Công nghệ thông tin' },
        language: { type: 'string', enum: ['vi', 'en'], example: 'en' },
        publisher: { type: 'string', example: 'Pearson' },
        publishedYear: { type: 'integer', example: 2017 },
        isbn: { type: 'string', example: '9780134494166' },
        description: { type: 'string', example: 'Sách test tạo mới từ Swagger' },
        coverUrl: { type: 'string', example: 'https://covers.openlibrary.org/b/isbn/9780134494166-L.jpg' },
      },
    },
  })
  create(@CurrentUser() user: AuthUser, @Body() rawBody: unknown) {
    const dto = parseZod(createBookSchema, rawBody);
    return this.booksService.create(user, dto);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Cập nhật thông tin đầu sách' })
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        title: { type: 'string', example: 'Clean Architecture (2nd Edition)' },
        author: { type: 'string', example: 'Robert C. Martin' },
        category: { type: 'string', example: 'Kỹ thuật phần mềm' },
        language: { type: 'string', enum: ['vi', 'en'], example: 'en' },
        publisher: { type: 'string', example: 'Pearson' },
        publishedYear: { type: 'integer', example: 2018 },
        isbn: { type: 'string', example: '9780134494166' },
        description: { type: 'string', example: 'Cập nhật mô tả đầu sách' },
        coverUrl: { type: 'string', nullable: true, example: null },
      },
    },
  })
  update(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() rawBody: unknown,
  ) {
    const dto = parseZod(updateBookSchema, rawBody);
    return this.booksService.update(user, id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Xóa mềm đầu sách (chặn nếu đang có bản sao được mượn)' })
  remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.booksService.remove(user, id);
  }

  @Post(':id/copies')
  @ApiOperation({ summary: 'Thêm bản sao vật lý mới cho đầu sách tại một chi nhánh' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['branchId', 'barcode'],
      properties: {
        branchId: { type: 'string', format: 'uuid', example: 'dán-branchId-vào-đây' },
        barcode: { type: 'string', example: 'HCM-TEST-001' },
        conditionNotes: { type: 'string', example: 'Sách mới nguyên seal' },
      },
    },
  })
  addCopy(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() rawBody: unknown,
  ) {
    const dto = parseZod(createBookCopySchema, rawBody);
    return this.booksService.addCopy(user, id, dto);
  }

  @Patch('copies/:copyId')
  @ApiOperation({ summary: 'Cập nhật tình trạng hoặc ghi chú của một bản sao' })
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        status: {
          type: 'string',
          enum: ['available', 'borrowed', 'reserved', 'damaged', 'lost', 'maintenance'],
          example: 'damaged',
        },
        conditionNotes: { type: 'string', example: 'Rách nhẹ bìa sau' },
      },
    },
  })
  updateCopy(
    @CurrentUser() user: AuthUser,
    @Param('copyId', ParseUUIDPipe) copyId: string,
    @Body() rawBody: unknown,
  ) {
    const dto = parseZod(updateBookCopySchema, rawBody);
    return this.booksService.updateCopy(user, copyId, dto);
  }

  @Delete('copies/:copyId')
  @ApiOperation({ summary: 'Xóa mềm bản sao sách tại chi nhánh' })
  removeCopy(@CurrentUser() user: AuthUser, @Param('copyId', ParseUUIDPipe) copyId: string) {
    return this.booksService.removeCopy(user, copyId);
  }
}