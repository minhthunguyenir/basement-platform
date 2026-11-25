import { ConcurrencyLimit } from './concurrency-limit';

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((r) => (resolve = r));
  return { promise, resolve };
}

describe('ConcurrencyLimit', () => {
  it('không bao giờ chạy quá max tác vụ cùng lúc, và chạy hết mọi tác vụ', async () => {
    const limit = new ConcurrencyLimit(2);
    let active = 0;
    let peak = 0;
    const gates = Array.from({ length: 5 }, deferred);

    const results = gates.map((gate, i) =>
      limit.run(async () => {
        active++;
        peak = Math.max(peak, active);
        await gate.promise;
        active--;
        return i;
      }),
    );
    // Mở từng cổng một; mỗi lần nhường event loop để tác vụ chờ kịp bắt đầu.
    for (const gate of gates) {
      await new Promise((r) => setImmediate(r));
      expect(active).toBeLessThanOrEqual(2);
      gate.resolve();
    }

    await expect(Promise.all(results)).resolves.toEqual([0, 1, 2, 3, 4]);
    expect(peak).toBe(2);
  });

  it('tác vụ lỗi vẫn trả suất chạy cho tác vụ sau', async () => {
    const limit = new ConcurrencyLimit(1);
    await expect(limit.run(() => Promise.reject(new Error('hỏng')))).rejects.toThrow('hỏng');
    await expect(limit.run(() => Promise.resolve('ok'))).resolves.toBe('ok');
  });

  it('max không hợp lệ: báo lỗi', () => {
    expect(() => new ConcurrencyLimit(0)).toThrow();
  });
});
