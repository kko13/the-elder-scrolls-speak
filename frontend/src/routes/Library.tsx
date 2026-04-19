import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type BookSummary } from '../api/client';
import { usePlayer } from '../store/player';

function fmt(sec?: number): string {
  if (!sec) return '–';
  const m = Math.floor(sec / 60);
  return `${m} min`;
}

export function Library() {
  const [books, setBooks] = useState<BookSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const setCurrent = usePlayer((s) => s.setCurrent);

  useEffect(() => {
    let cancelled = false;
    api.listBooks('skyrim')
      .then((r) => { if (!cancelled) setBooks(r.books); })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'failed to load'));
    return () => { cancelled = true; };
  }, []);

  const onPlay = async (id: string) => {
    const r = await api.getBook(id);
    setCurrent(r.book);
  };

  if (error) return <div className="error">Couldn't load library: {error}</div>;
  if (!books.length) return <div className="empty">No books yet — run the ingestion Lambda.</div>;

  return (
    <div className="library-grid">
      {books.map((b) => (
        <div key={b.book_id} className="library-row">
          <div>
            <div className="title">
              <Link to={`/book/${b.book_id}`}>{b.title}</Link>
            </div>
            <div className="author">{b.author ?? 'Unknown'}</div>
          </div>
          <div className="author">{b.voice_id ?? ''}</div>
          <div className="duration">{fmt(b.audio_duration_sec)}</div>
          <button onClick={() => onPlay(b.book_id)}>▶</button>
        </div>
      ))}
    </div>
  );
}
