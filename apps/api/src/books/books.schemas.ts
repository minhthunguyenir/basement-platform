import { z } from 'zod';

export const copyStatusEnum = z.enum(['available', 'on_loan', 'damaged', 'lost']);
export type CopyStatus = z.infer<typeof copyStatusEnum>;

export const listBooksQuerySchema = z.object({
  q: z.string().trim().max(200).optional(),
  category: z.string().trim().max(100).optional(),
  language: z.enum(['vi', 'en']).optional(),
  branchId: z.string().uuid().optional(),
  availableOnly: z
    .enum(['true', 'false'])
    .transform((v) => v === 'true')
    .optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type ListBooksQueryDto = z.infer<typeof listBooksQuerySchema>;

export const createBookSchema = z.object({
  title: z.string().trim().min(1, 'Tên sách không được để trống').max(500),
  authors: z.string().trim().min(1, 'Tác giả không được để trống').max(500),
  isbn: z.string().trim().max(20).nullable().optional(),
  language: z.enum(['vi', 'en']).default('vi'),
  description: z.string().trim().min(1, 'Mô tả không được để trống').max(5000),
  categories: z.array(z.string().trim().min(1)).min(1, 'Chọn ít nhất 1 thể loại'),
  coverUrl: z.string().url().nullable().optional(),
});
export type CreateBookDto = z.infer<typeof createBookSchema>;

export const updateBookSchema = createBookSchema.partial();
export type UpdateBookDto = z.infer<typeof updateBookSchema>;

export const createBookCopySchema = z.object({
  branchId: z.string().uuid('branchId phải là UUID hợp lệ'),
  barcode: z.string().trim().min(3).max(64),
  status: copyStatusEnum.default('available'),
  notes: z.string().trim().max(500).nullable().optional(),
});
export type CreateBookCopyDto = z.infer<typeof createBookCopySchema>;

export const updateBookCopySchema = z.object({
  status: copyStatusEnum.optional(),
  notes: z.string().trim().max(500).nullable().optional(),
});
export type UpdateBookCopyDto = z.infer<typeof updateBookCopySchema>;