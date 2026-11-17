/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: { DEFAULT: '#0f5c4d', dark: '#0b4539' },
        paper: '#f6f5f1',
        ink: '#1f2421',
      },
    },
  },
  plugins: [],
};
