module.exports = {
  ...require('./packages/shared-configs/eslint.js'),
  ignorePatterns: [
    '**/*',
    '!src/**/*',
    '!packages/**/*',
    '!apps/**/*',
    '!tools/**/*',
    'node_modules/**/*',
    'dist/**/*',
    'build/**/*',
    'coverage/**/*',
    '*.log',
    '.nx/**/*',
    'tmp/**/*'
  ],
  overrides: [
    {
      files: ['*.ts', '*.tsx', '*.js', '*.jsx'],
      rules: {}
    },
    {
      files: ['*.ts', '*.tsx'],
      extends: ['@typescript-eslint/recommended'],
      rules: {}
    },
    {
      files: ['*.js', '*.jsx'],
      rules: {}
    }
  ]
};