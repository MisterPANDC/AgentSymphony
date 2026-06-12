import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#18181b",
        panel: "#f7f7f4",
        line: "#deded7",
        moss: "#52684f",
        rust: "#9a5b3e"
      },
      boxShadow: {
        rail: "0 1px 0 rgba(24, 24, 27, 0.08)"
      }
    }
  },
  plugins: []
} satisfies Config;
