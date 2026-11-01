fn main() {
    // sqlx::migrate! embeds migration files at compile time; rebuild when they change.
    println!("cargo:rerun-if-changed=migrations");
}
