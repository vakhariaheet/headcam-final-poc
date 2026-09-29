export const PORT: number = Number(process.env.PORT) || 4000;

// Defaults match db/docker-compose.yml's local dev credentials.
const DEFAULT_DATABASE_URL = 'postgres://umpirehat:umpirehat_dev@localhost:5432/umpirehat';
export const DATABASE_URL: string = process.env.DATABASE_URL ?? DEFAULT_DATABASE_URL;

// Dev-only default — override with a real secret via JWT_SECRET in any
// deployed environment.
export const JWT_SECRET: string = process.env.JWT_SECRET ?? 'umpirehat-dev-secret-change-me';

export const NODE_ENV: string = process.env.NODE_ENV ?? 'development';
const DEFAULT_LOG_LEVEL = NODE_ENV === 'production' ? 'info' : 'debug';
export const LOG_LEVEL: string = process.env.LOG_LEVEL ?? DEFAULT_LOG_LEVEL;

export const SMTP_HOST: string | undefined = process.env.SMTP_HOST;
export const SMTP_PORT: number = Number(process.env.SMTP_PORT) || 587;
export const SMTP_USER: string | undefined = process.env.SMTP_USER;
export const SMTP_PASSWORD: string | undefined = process.env.SMTP_PASSWORD;
export const SMTP_FROM: string = process.env.SMTP_FROM
  ?? 'CreasePoint <no-reply@creasepoint.local>';
