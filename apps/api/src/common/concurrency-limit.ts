/**
 * Giới hạn số tác vụ chạy cùng lúc; tác vụ vượt mức xếp hàng chờ theo thứ tự đến.
 * Dùng cho việc tốn bộ nhớ như kiểm tra mật khẩu scrypt (~128 MiB mỗi lần).
 */
export class ConcurrencyLimit {
  private running = 0;
  private readonly waiting: Array<() => void> = [];

  constructor(private readonly max: number) {
    if (!Number.isInteger(max) || max < 1) {
      throw new Error('ConcurrencyLimit: max phải là số nguyên >= 1');
    }
  }

  async run<T>(task: () => Promise<T>): Promise<T> {
    if (this.running >= this.max) {
      await new Promise<void>((resolve) => this.waiting.push(resolve));
    } else {
      this.running++;
    }
    try {
      return await task();
    } finally {
      // Chuyển thẳng suất chạy cho tác vụ đang chờ; không có ai chờ thì trả suất lại.
      const next = this.waiting.shift();
      if (next) {
        next();
      } else {
        this.running--;
      }
    }
  }
}
