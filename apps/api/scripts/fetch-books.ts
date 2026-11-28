import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

export interface SeedBookItem {
  title: string;
  authors: string;
  isbn: string | null;
  language: 'vi' | 'en';
  description: string;
  categories: string[];
}

const OPEN_LIBRARY_QUERIES: Array<{ q: string; lang: 'vi' | 'en'; category: string }> = [
  // Tiếng Việt
  { q: 'văn học việt nam', lang: 'vi', category: 'Văn học' },
  { q: 'kinh tế quản trị kinh doanh', lang: 'vi', category: 'Kinh tế & Quản trị' },
  { q: 'tâm lý học kỹ năng sống', lang: 'vi', category: 'Tâm lý & Kỹ năng' },
  { q: 'lịch sử văn hóa việt nam', lang: 'vi', category: 'Khoa học & Xã hội' },
  { q: 'công nghệ thông tin lập trình', lang: 'vi', category: 'Công nghệ thông tin' },
  { q: 'triết học giáo dục nghệ thuật', lang: 'vi', category: 'Thiết kế & Kiến trúc' },
  // Tiếng Anh
  { q: 'software engineering distributed systems', lang: 'en', category: 'Công nghệ thông tin' },
  { q: 'artificial intelligence machine learning', lang: 'en', category: 'Công nghệ thông tin' },
  { q: 'startup management economics strategy', lang: 'en', category: 'Kinh tế & Quản trị' },
  { q: 'cognitive psychology habits behavioral', lang: 'en', category: 'Tâm lý & Kỹ năng' },
  { q: 'classic literature modern fiction', lang: 'en', category: 'Văn học' },
  { q: 'product design typography architecture', lang: 'en', category: 'Thiết kế & Kiến trúc' },
  { q: 'physics philosophy world history', lang: 'en', category: 'Khoa học & Xã hội' },
];

function cleanText(input: string): string {
  return input.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
}

function buildDescription(doc: any, category: string, lang: 'vi' | 'en'): string {
  const parts: string[] = [];

  if (typeof doc.first_sentence === 'string') {
    parts.push(doc.first_sentence);
  } else if (Array.isArray(doc.first_sentence) && doc.first_sentence.length > 0) {
    parts.push(String(doc.first_sentence[0]));
  }

  if (Array.isArray(doc.subject) && doc.subject.length > 0) {
    const subjects = doc.subject.slice(0, 8).join(', ');
    parts.push(
      lang === 'vi'
        ? `Chủ đề chính bao gồm: ${subjects}.`
        : `Key topics and subjects covered: ${subjects}.`,
    );
  }

  const title = cleanText(String(doc.title ?? ''));
  const authors = Array.isArray(doc.author_name) ? doc.author_name.join(', ') : '';
  const year = doc.first_publish_year ? ` (${doc.first_publish_year})` : '';

  parts.push(
    lang === 'vi'
      ? `Cuốn sách "${title}"${year} của tác giả ${authors} thuộc danh mục ${category}, cung cấp kiến thức nền tảng, góc nhìn phân tích chuyên sâu và tài liệu tham khảo hữu ích cho bạn đọc nghiên cứu và học tập tại không gian tự học.`
      : `"${title}"${year} by ${authors} is a comprehensive work in ${category}, offering foundational concepts, analytical perspectives, and practical reference material for students and researchers.`,
  );

  return cleanText(parts.join(' '));
}

async function fetchFromOpenLibrary(
  q: string,
  lang: 'vi' | 'en',
  category: string,
): Promise<SeedBookItem[]> {
  const url =
    `https://openlibrary.org/search.json?q=${encodeURIComponent(q)}` +
    `&language=${lang === 'vi' ? 'vie' : 'eng'}&limit=50` +
    `&fields=title,author_name,isbn,first_publish_year,subject,first_sentence`;

  const res = await fetch(url, {
    headers: { 'User-Agent': 'BasementPlatformThesis/1.0 (student-project)' },
  });

  if (!res.ok) {
    console.warn(`Cảnh báo HTTP ${res.status} với query: ${q}`);
    return [];
  }

  const json = (await res.json()) as { docs?: any[] };
  const collected: SeedBookItem[] = [];

  for (const doc of json.docs ?? []) {
    if (!doc?.title || !Array.isArray(doc.author_name) || doc.author_name.length === 0) continue;

    const title = cleanText(String(doc.title)).slice(0, 500);
    const authors = cleanText(doc.author_name.slice(0, 3).join(', '));
    const description = buildDescription(doc, category, lang);

    if (title.length < 2 || authors.length < 2 || description.length < 120) continue;

    let validIsbn: string | null = null;
    if (Array.isArray(doc.isbn)) {
      const found = doc.isbn.find((code: string) => {
        const c = String(code).replace(/[^0-9Xx]/g, '');
        return c.length === 13 || c.length === 10;
      });
      if (found) {
        validIsbn = String(found).replace(/[^0-9Xx]/g, '').slice(0, 20);
      }
    }

    collected.push({
      title,
      authors,
      isbn: validIsbn,
      language: lang,
      description,
      categories: [category],
    });
  }

  return collected;
}

async function main() {
  const allBooks: SeedBookItem[] = [];

  for (const query of OPEN_LIBRARY_QUERIES) {
    console.log(`Đang tải [${query.lang}] ${query.category}...`);
    const items = await fetchFromOpenLibrary(query.q, query.lang, query.category);
    console.log(`  -> Lấy được ${items.length} cuốn`);
    allBooks.push(...items);
  }

  const seenIsbn = new Set<string>();
  const seenTitleAuthor = new Set<string>();
  const cleaned: SeedBookItem[] = [];

  for (const book of allBooks) {
    if (book.isbn) {
      if (seenIsbn.has(book.isbn)) continue;
      seenIsbn.add(book.isbn);
    }

    const taKey = `${book.title.toLowerCase()}::${book.authors.toLowerCase()}`;
    if (seenTitleAuthor.has(taKey)) continue;
    seenTitleAuthor.add(taKey);

    cleaned.push(book);
    if (cleaned.length >= 420) break;
  }

  const currentDir = path.dirname(fileURLToPath(import.meta.url));
  const outFile = path.join(currentDir, '../prisma/data/books.seed.json');
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, JSON.stringify(cleaned, null, 2), 'utf-8');

  const viCount = cleaned.filter((b) => b.language === 'vi').length;
  const enCount = cleaned.filter((b) => b.language === 'en').length;
  const emptyDescCount = cleaned.filter((b) => !b.description || b.description.length < 120).length;

  console.log('-----------------------------------------');
  console.log(`Tổng số đầu sách sạch : ${cleaned.length}`);
  console.log(`Tiếng Việt (vi)       : ${viCount} (${cleaned.length ? Math.round((viCount / cleaned.length) * 100) : 0}%)`);
  console.log(`Tiếng Anh (en)        : ${enCount} (${cleaned.length ? Math.round((enCount / cleaned.length) * 100) : 0}%)`);
  console.log(`Sách thiếu mô tả      : ${emptyDescCount}`);
  console.log(`Đã lưu tại            : ${outFile}`);
}

main().catch((err) => {
  console.error('Lỗi tải dữ liệu sách:', err);
  process.exit(1);
});