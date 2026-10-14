// Lint rules for the browser code. Formatting is Prettier's job, run from the
// repository root; this checks for likely mistakes.
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  eslint.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
  },
  { ignores: ['dist/', 'eslint.config.js'] },
);
