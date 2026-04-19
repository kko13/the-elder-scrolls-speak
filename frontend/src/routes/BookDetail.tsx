import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api, type BookDetail as BookDetailT } from '../api/client';
import { usePlayer } from '../store/player';

export function BookDetail() {
  const { bookId } = useParams<{ bookId: string }>();
  const [book, setBook] = useState<BookDetailT | null>(null);
  const [error, setError] = useState<string | null>(null);
  const setCurrent = usePlayer((s) => s.setCurrent);

  useEffect(() => {
    if (!bookId) return;
    let cancelled = false;
    api.getBook(bookId)
      .then((r) => { if (!cancelled) setBook(r.book); })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'failed'));
    return () => { cancelled = true; };
  }, [bookId]);

  if (error) return <div className="error">{error}</div>;
  if (!book) return <div className="empty">Loading…</div>;

  return (
    <div className="book-detail">
      <h2>{book.title}</h2>
      <div className="meta">
        by {book.author ?? 'Unknown'}
        {book.audio_duration_sec ? ` · ${Math.round(book.audio_duration_sec / 60)} min` : ''}
        {book.voice_id ? ` · narrated by ${book.voice_id}` : ''}
      </div>
      {book.summary && <p className="summary">{book.summary}</p>}

      {book.in_game_locations?.length ? (
        <>
          <h3>Where to find it</h3>
          <ul className="locations">
            {book.in_game_locations.map((l, i) => (
              <li key={i}>{[l.region, l.cell, l.notes].filter(Boolean).join(' — ')}</li>
            ))}
          </ul>
        </>
      ) : null}

      <p>
        Sources:{' '}
        {book.imperial_library_url && (
          <a href={book.imperial_library_url} target="_blank" rel="noreferrer">Imperial Library</a>
        )}
        {book.imperial_library_url && book.uesp_url && ' · '}
        {book.uesp_url && (
          <a href={book.uesp_url} target="_blank" rel="noreferrer">UESP</a>
        )}
      </p>

      <button onClick={() => setCurrent(book)} disabled={!book.audio}>
        {book.audio ? '▶ Play' : 'Audio not yet generated'}
      </button>
    </div>
  );
}
