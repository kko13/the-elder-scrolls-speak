import { useEffect, useRef } from 'react';
import { usePlayer } from '../store/player';

function fmt(sec?: number): string {
  if (!sec || !isFinite(sec)) return '–:–';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function Player() {
  const current = usePlayer((s) => s.current);
  const loadedTime = usePlayer((s) => s.loadedTime);
  const syncTime = usePlayer((s) => s.syncTime);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Persist progress every 5 seconds while playing.
  useEffect(() => {
    if (!current) return;
    const a = audioRef.current;
    if (!a) return;
    const id = window.setInterval(() => {
      if (!a.paused) syncTime(a.currentTime);
    }, 5000);
    return () => window.clearInterval(id);
  }, [current, syncTime]);

  // Resume from persisted offset on mount / book change.
  useEffect(() => {
    const a = audioRef.current;
    if (a && loadedTime > 0) {
      a.currentTime = loadedTime;
    }
  }, [current?.book_id, loadedTime]);

  if (!current) {
    return (
      <div className="player">
        <div className="now-playing"><span className="author">Nothing playing</span></div>
        <div />
        <div className="right" />
      </div>
    );
  }

  return (
    <div className="player">
      <div className="now-playing">
        <div className="title">{current.title}</div>
        <div className="author">{current.author ?? 'Unknown'}</div>
      </div>
      <audio
        ref={audioRef}
        src={current.audio?.url}
        controls
        autoPlay
        preload="metadata"
        onEnded={() => syncTime(0)}
      />
      <div className="right">{fmt(current.audio_duration_sec)}</div>
    </div>
  );
}
