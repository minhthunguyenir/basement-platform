import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AuthUsersService } from '../auth/auth-users.service';
import type { AuthUser } from '../auth/auth.types';
import type {
  CreateBookCopyDto,
  CreateBookDto,
  ListBooksQueryDto,
  UpdateBookCopyDto,
  UpdateBookDto,
} from './books.schemas';

@Injectable()
export class BooksService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly authUsers: AuthUsersService,
  ) {}

  /** Kiểm tra quyền quản lý kho sách (owner, branch_manager, staff). */
  private async assertStaffOrManager(user: AuthUser, targetBranchId?: string) {
    const roles = await this.authUsers.findRoles(user);
    const staffRoles = roles.filter((r) =>
      ['owner', 'branch_manager', 'staff'].includes(r.role),
    );

    if (staffRoles.length === 0) {
      throw new ForbiddenException('Chỉ nhân viên hoặc quản lý mới có quyền thao tác kho sách.');
    }

    // Owner hoặc role cấp chuỗi (branch === null) có quyền toàn bộ chi nhánh
    const hasChainAccess = staffRoles.some((r) => r.role === 'owner' || r.branch === null);
    if (hasChainAccess || !targetBranchId) return;

    const hasBranchAccess = staffRoles.some((r) => r.branch?.id === targetBranchId);
    if (!hasBranchAccess) {
      throw new ForbiddenException('Bạn không có quyền quản lý bản sao tại chi nhánh này.');
    }
  }

  /** Danh sách đầu sách kèm thống kê số lượng bản sao sẵn có theo từng chi nhánh. */
  async findAll(user: AuthUser, query: ListBooksQueryDto) {
    const { q, category, language, branchId, availableOnly, page, limit } = query;
    const skip = (page - 1) * limit;

    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const where: Prisma.booksWhereInput = {
          organization_id: user.organizationId,
          deleted_at: null,
          ...(language ? { language } : {}),
          ...(category ? { categories: { has: category } } : {}),
          ...(q
            ? {
                OR: [
                  { title: { contains: q, mode: 'insensitive' } },
                  { authors: { contains: q, mode: 'insensitive' } },
                  { isbn: { contains: q, mode: 'insensitive' } },
                  { description: { contains: q, mode: 'insensitive' } },
                ],
              }
            : {}),
          ...(branchId || availableOnly
            ? {
                book_copies: {
                  some: {
                    deleted_at: null,
                    ...(branchId ? { branch_id: branchId } : {}),
                    ...(availableOnly ? { status: 'available' } : {}),
                  },
                },
              }
            : {}),
        };

        const [total, items] = await Promise.all([
          tx.books.count({ where }),
          tx.books.findMany({
            where,
            skip,
            take: limit,
            orderBy: { created_at: 'desc' },
            include: {
              book_copies: {
                where: {
                  deleted_at: null,
                  ...(branchId ? { branch_id: branchId } : {}),
                },
                select: {
                  id: true,
                  status: true,
                  branch_id: true,
                  branches: { select: { id: true, code: true, name: true } },
                },
              },
            },
          }),
        ]);

        const data = items.map((book) => {
          const branchSummaryMap = new Map<
            string,
            { branchId: string; branchCode: string; branchName: string; total: number; available: number }
          >();

          for (const copy of book.book_copies) {
            const b = copy.branches;
            if (!branchSummaryMap.has(b.id)) {
              branchSummaryMap.set(b.id, {
                branchId: b.id,
                branchCode: b.code,
                branchName: b.name,
                total: 0,
                available: 0,
              });
            }
            const entry = branchSummaryMap.get(b.id)!;
            entry.total += 1;
            if (copy.status === 'available') entry.available += 1;
          }

          const { book_copies, ...bookInfo } = book;
          return {
            ...bookInfo,
            totalCopies: book_copies.length,
            availableCopies: book_copies.filter((c) => c.status === 'available').length,
            branches: Array.from(branchSummaryMap.values()),
          };
        });

        return {
          data,
          meta: {
            page,
            limit,
            total,
            totalPages: Math.ceil(total / limit),
          },
        };
      },
    );
  }

  /** Chi tiết 1 đầu sách và danh sách toàn bộ bản sao vật lý theo chi nhánh. */
  async findOne(user: AuthUser, bookId: string) {
    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const book = await tx.books.findFirst({
          where: { id: bookId, organization_id: user.organizationId, deleted_at: null },
          include: {
            book_copies: {
              where: { deleted_at: null },
              orderBy: { barcode: 'asc' },
              include: {
                branches: { select: { id: true, code: true, name: true } },
              },
            },
          },
        });

        if (!book) {
          throw new NotFoundException('Không tìm thấy đầu sách.');
        }

        return book;
      },
    );
  }

  /** Thêm đầu sách mới vào danh mục dùng chung của chuỗi. */
  async create(user: AuthUser, dto: CreateBookDto) {
    await this.assertStaffOrManager(user);

    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        if (dto.isbn) {
          const dup = await tx.books.findFirst({
            where: { organization_id: user.organizationId, isbn: dto.isbn, deleted_at: null },
          });
          if (dup) {
            throw new ConflictException(`Đã tồn tại đầu sách với mã ISBN ${dto.isbn}.`);
          }
        }

        return tx.books.create({
          data: {
            organization_id: user.organizationId,
            title: dto.title,
            authors: dto.authors,
            isbn: dto.isbn ?? null,
            language: dto.language,
            description: dto.description,
            categories: dto.categories,
            cover_url: dto.coverUrl ?? null,
          },
        });
      },
    );
  }

  /** Cập nhật thông tin đầu sách. */
  async update(user: AuthUser, bookId: string, dto: UpdateBookDto) {
    await this.assertStaffOrManager(user);

    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const existing = await tx.books.findFirst({
          where: { id: bookId, organization_id: user.organizationId, deleted_at: null },
        });
        if (!existing) {
          throw new NotFoundException('Không tìm thấy đầu sách.');
        }

        if (dto.isbn && dto.isbn !== existing.isbn) {
          const dup = await tx.books.findFirst({
            where: {
              organization_id: user.organizationId,
              isbn: dto.isbn,
              deleted_at: null,
              id: { not: bookId },
            },
          });
          if (dup) {
            throw new ConflictException(`Mã ISBN ${dto.isbn} đã được sử dụng cho đầu sách khác.`);
          }
        }

        return tx.books.update({
          where: { id: bookId },
          data: {
            ...(dto.title !== undefined ? { title: dto.title } : {}),
            ...(dto.authors !== undefined ? { authors: dto.authors } : {}),
            ...(dto.isbn !== undefined ? { isbn: dto.isbn } : {}),
            ...(dto.language !== undefined ? { language: dto.language } : {}),
            ...(dto.description !== undefined ? { description: dto.description } : {}),
            ...(dto.categories !== undefined ? { categories: dto.categories } : {}),
            ...(dto.coverUrl !== undefined ? { cover_url: dto.coverUrl } : {}),
          },
        });
      },
    );
  }

  /** Xóa mềm đầu sách (chặn nếu đang có bản sao được mượn). */
  async remove(user: AuthUser, bookId: string) {
    await this.assertStaffOrManager(user);

    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const existing = await tx.books.findFirst({
          where: { id: bookId, organization_id: user.organizationId, deleted_at: null },
        });
        if (!existing) {
          throw new NotFoundException('Không tìm thấy đầu sách.');
        }

        const activeLoansCount = await tx.book_copies.count({
          where: {
            book_id: bookId,
            deleted_at: null,
            status: 'on_loan',
          },
        });
        if (activeLoansCount > 0) {
          throw new BadRequestException(
            `Không thể xóa đầu sách vì đang có ${activeLoansCount} bản sao được khách mượn.`,
          );
        }

        const now = new Date();
        await tx.book_copies.updateMany({
          where: { book_id: bookId, deleted_at: null },
          data: { deleted_at: now },
        });

        await tx.books.update({
          where: { id: bookId },
          data: { deleted_at: now },
        });

        return { deleted: true, id: bookId };
      },
    );
  }

  /** Thêm bản sao vật lý mới cho một đầu sách tại chi nhánh. */
  async addCopy(user: AuthUser, bookId: string, dto: CreateBookCopyDto) {
    await this.assertStaffOrManager(user, dto.branchId);

    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const book = await tx.books.findFirst({
          where: { id: bookId, organization_id: user.organizationId, deleted_at: null },
        });
        if (!book) {
          throw new NotFoundException('Không tìm thấy đầu sách.');
        }

        const dupBarcode = await tx.book_copies.findFirst({
          where: { organization_id: user.organizationId, barcode: dto.barcode, deleted_at: null },
        });
        if (dupBarcode) {
          throw new ConflictException(`Mã barcode ${dto.barcode} đã tồn tại trong hệ thống.`);
        }

        return tx.book_copies.create({
          data: {
            organization_id: user.organizationId,
            branch_id: dto.branchId,
            book_id: bookId,
            barcode: dto.barcode,
            status: dto.status,
          },
          include: {
            branches: { select: { id: true, code: true, name: true } },
          },
        });
      },
    );
  }

  /** Cập nhật tình trạng hoặc ghi chú của một bản sao (vd: đánh dấu hư hỏng/thất lạc). */
  async updateCopy(user: AuthUser, copyId: string, dto: UpdateBookCopyDto) {
    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const copy = await tx.book_copies.findFirst({
          where: { id: copyId, organization_id: user.organizationId, deleted_at: null },
        });
        if (!copy) {
          throw new NotFoundException('Không tìm thấy bản sao sách.');
        }

        await this.assertStaffOrManager(user, copy.branch_id);

        if (copy.status === 'on_loan' && dto.status && dto.status !== 'on_loan') {
          throw new BadRequestException(
            'Bản sao đang trong phiếu mượn, vui lòng thực hiện trả sách trước khi đổi trạng thái.',
          );
        }

        return tx.book_copies.update({
          where: { id: copyId },
          data: {
            ...(dto.status !== undefined ? { status: dto.status } : {}),
            ...(dto.notes !== undefined ? { notes: dto.notes } : {}),
          },
          include: {
            branches: { select: { id: true, code: true, name: true } },
          },
        });
      },
    );
  }

  /** Xóa mềm một bản sao vật lý tại chi nhánh. */
  async removeCopy(user: AuthUser, copyId: string) {
    return this.prisma.withContext(
      { organizationId: user.organizationId, userId: user.id },
      async (tx) => {
        const copy = await tx.book_copies.findFirst({
          where: { id: copyId, organization_id: user.organizationId, deleted_at: null },
        });
        if (!copy) {
          throw new NotFoundException('Không tìm thấy bản sao sách.');
        }

        await this.assertStaffOrManager(user, copy.branch_id);

        if (copy.status === 'on_loan') {
          throw new BadRequestException('Không thể xóa bản sao đang được mượn.');
        }

        await tx.book_copies.update({
          where: { id: copyId },
          data: { deleted_at: new Date() },
        });

        return { deleted: true, id: copyId };
      },
    );
  }
}