import './globals.css';

export const metadata = { title: 'Money Tracker', description: 'Secure personal and business money management' };

export default function RootLayout({ children }) {
  return <html lang="bn"><body>{children}</body></html>;
}
