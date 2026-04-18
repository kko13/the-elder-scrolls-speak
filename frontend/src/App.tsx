import { NavLink, Route, Routes } from 'react-router-dom';
import { Player } from './components/Player';
import { Library } from './routes/Library';
import { BookDetail } from './routes/BookDetail';

export default function App() {
  return (
    <div className="app">
      <header className="topbar">
        <h1>The Elder Scrolls Speak</h1>
        <nav>
          <NavLink to="/" end>Library</NavLink>
        </nav>
      </header>
      <main className="content">
        <Routes>
          <Route path="/" element={<Library />} />
          <Route path="/book/:bookId" element={<BookDetail />} />
        </Routes>
      </main>
      <Player />
    </div>
  );
}
