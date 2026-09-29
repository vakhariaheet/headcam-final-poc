import { Pool } from 'pg';

const DEFAULT_DATABASE_URL = 'postgres://umpirehat:umpirehat_dev@localhost:5432/umpirehat';
const DATABASE_URL = process.env.DATABASE_URL ?? DEFAULT_DATABASE_URL;

export const pool = new Pool({ connectionString: DATABASE_URL });
