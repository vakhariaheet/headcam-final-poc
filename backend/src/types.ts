export interface AppUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string | null;
  role: string;
}

// Row shape as returned directly from the `users` table (spec §7.2, plus
// the password_hash column added in db/init/002_add_auth.sql).
export interface UserRow {
  id: string;
  email: string;
  first_name: string;
  last_name: string | null;
  role: string;
  password_hash: string;
}

export function toAppUser(row: UserRow): AppUser {
  return {
    id: row.id,
    email: row.email,
    firstName: row.first_name,
    lastName: row.last_name,
    role: row.role,
  };
}
