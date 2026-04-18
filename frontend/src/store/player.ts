// Zustand store for the now-playing book + persistence to localStorage.
// We persist (book_id, currentTime) so a refresh resumes where the user left off.

import { create } from 'zustand';
import type { BookDetail } from '../api/client';

interface PersistedState {
  bookId: string | null;
  currentTime: number;
}

const KEY = 'tes-speak:player';

function loadPersisted(): PersistedState {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as PersistedState) : { bookId: null, currentTime: 0 };
  } catch {
    return { bookId: null, currentTime: 0 };
  }
}

function savePersisted(s: PersistedState) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); } catch { /* quota — ignore */ }
}

interface PlayerStore {
  current: BookDetail | null;
  loadedTime: number;        // seconds to seek to on next <audio> mount
  setCurrent: (book: BookDetail) => void;
  syncTime: (t: number) => void;
}

const initial = loadPersisted();

export const usePlayer = create<PlayerStore>((set, get) => ({
  current: null,
  loadedTime: initial.bookId ? initial.currentTime : 0,
  setCurrent: (book) => {
    const prev = get().current;
    const sameBook = prev?.book_id === book.book_id;
    set({
      current: book,
      loadedTime: sameBook ? get().loadedTime : 0,
    });
    savePersisted({ bookId: book.book_id, currentTime: sameBook ? get().loadedTime : 0 });
  },
  syncTime: (t) => {
    const cur = get().current;
    if (!cur) return;
    savePersisted({ bookId: cur.book_id, currentTime: t });
  },
}));

export const persistedBookId = initial.bookId;
