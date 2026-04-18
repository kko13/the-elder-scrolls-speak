// Thin fetch wrapper. The CloudFront SPA distribution proxies /api/* to API
// Gateway, so we always hit a relative /api path in production. In dev, set
// VITE_API_BASE in `.env.development` to point at the deployed API endpoint.

const BASE = import.meta.env.VITE_API_BASE ?? '/api';

export interface BookSummary {
  book_id: string;
  title: string;
  author?: string;
  audio_duration_sec?: number;
  voice_id?: string;
  summary?: string;
}

export interface InGameLocation {
  region?: string;
  cell?: string;
  notes?: string;
}

export interface BookDetail extends BookSummary {
  game: string;
  in_game_locations?: InGameLocation[];
  imperial_library_url?: string;
  uesp_url?: string;
  word_count?: number;
  audio?: { url: string; expires_at: string } | null;
}

async function jsonGet<T>(path: string): Promise<T> {
  const r = await fetch(`${BASE}${path}`);
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.json() as Promise<T>;
}

export const api = {
  listBooks: (game = 'skyrim', cursor?: string) =>
    jsonGet<{ books: BookSummary[]; next_cursor: string | null }>(
      `/books?game=${game}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`,
    ),
  listAuthors: (game = 'skyrim') =>
    jsonGet<{ authors: { name: string; book_count: number }[] }>(`/authors?game=${game}`),
  getBook: (bookId: string) => jsonGet<{ book: BookDetail }>(`/books/${bookId}`),
};
