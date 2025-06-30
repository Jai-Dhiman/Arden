use async_trait::async_trait;
use worker::{Context, Result, D1Database, Env, console_log, Date}; // Added Env, D1Database, Date, console_log
use crate::types::{
    Note, CreateNoteInput, UpdateNoteInput, NotesQueryParams, NoteFromD1, // Notes types
    HealthResponse, UserCount // Health types
};
use uuid::Uuid;
use chrono::Utc;

// --- Health Service ---
#[async_trait]
pub trait RpcHealthService {
    async fn check_health(&self, ctx: Context) -> Result<HealthResponse>;
}

pub struct HealthServiceImpl;

#[async_trait]
impl RpcHealthService for HealthServiceImpl {
    async fn check_health(&self, ctx: Context) -> Result<HealthResponse> {
        let d1 = ctx.env.d1("DB")?;
        let statement = d1.prepare("SELECT count(*) as count FROM users");

        console_log!("Executing SQL for health check: {}", "SELECT count(*) as count FROM users");

        let result_opt: Option<UserCount> = match statement.first(None).await {
            Ok(res) => res,
            Err(e) => {
                console_error!("Health check database query failed: {}", e);
                return Err(e.into());
            }
        };

        console_log!("Health check query result: {:?}", result_opt);

        let db_check = match result_opt {
            Some(user_count) if user_count.count > 0 => "records exist".to_string(),
            Some(_) => "no records".to_string(),
            None => "query returned no rows".to_string(),
        };

        Ok(HealthResponse {
            status: "ok".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            database: "connected".to_string(),
            db_check,
        })
    }
}

// --- Notes Service ---
#[async_trait]
pub trait RpcNotesService {
    async fn get_notes(&self, ctx: Context, params: NotesQueryParams) -> Result<Vec<Note>>;
    async fn get_note(&self, ctx: Context, id: String) -> Result<Option<Note>>;
    async fn create_note(&self, ctx: Context, input: CreateNoteInput) -> Result<Note>;
    async fn update_note(&self, ctx: Context, id: String, input: UpdateNoteInput) -> Result<Note>;
    async fn delete_note(&self, ctx: Context, id: String) -> Result<String>;
}

pub struct NotesServiceImpl;

#[async_trait]
impl RpcNotesService for NotesServiceImpl {
    async fn create_note(&self, ctx: Context, input: CreateNoteInput) -> Result<Note> {
        let db = ctx.env.d1("DB")?;

        let note_id = Uuid::new_v4().to_string();
        let user_id = "user-1";
        let now_ts = Utc::now().to_rfc3339();
        let tags_json = serde_json::to_string(&input.tags)
            .map_err(|e| worker::Error::RustError(format!("Failed to serialize tags: {}", e)))?;

        let statement = db.prepare(
            "INSERT INTO notes (id, userId, title, content, tags, favorite, archived, createdAt, updatedAt) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
        )
        .bind(&[
            note_id.clone().into(),
            user_id.into(),
            input.title.into(),
            input.content.into(),
            tags_json.into(),
            (if input.favorite { 1 } else { 0 }).into(),
            0.into(),
            now_ts.clone().into(),
            now_ts.clone().into(),
        ])?;

        statement.run().await.map_err(|e| {
            console_error!("Error inserting note: {:?}", e);
            e
        })?;
        console_log!("Successfully inserted note with id: {}", note_id);

        let query_new_note = db.prepare("SELECT id, userId, title, content, tags, favorite, archived, createdAt, updatedAt FROM notes WHERE id = ?1")
            .bind(&[note_id.into()])?;

        let d1_note_result: Option<NoteFromD1> = query_new_note.first(None).await?;

        d1_note_result.map(Note::from).ok_or_else(|| worker::Error::RustError("Failed to retrieve created note".to_string()))
    }

    async fn get_notes(&self, ctx: Context, params: NotesQueryParams) -> Result<Vec<Note>> {
        let db = ctx.env.d1("DB")?;
        let user_id = "user-1";

        let mut query_builder = String::from("SELECT id, userId, title, content, tags, favorite, archived, createdAt, updatedAt FROM notes WHERE userId = ?1");
        let mut bindings: Vec<worker::query::QueryArgument> = vec![user_id.into()];
        let mut arg_idx = 2; // Start bindings from ?2

        // Archived filter: defaults to false (0) if not specified
        let archived_val = params.archived.unwrap_or(false);
        query_builder.push_str(&format!(" AND archived = ?{}", arg_idx));
        bindings.push((if archived_val { 1 } else { 0 }).into());
        arg_idx += 1;

        if let Some(favorite) = params.favorite {
            query_builder.push_str(&format!(" AND favorite = ?{}", arg_idx));
            bindings.push((if favorite { 1 } else { 0 }).into());
            arg_idx += 1;
        }

        if let Some(search_term) = &params.search { // Use reference here
            if !search_term.is_empty() {
                // D1 requires distinct placeholders for each LIKE operand if their values might differ,
                // or if you want to be explicit. If the value is the same, one placeholder can be reused
                // by some DBs, but D1 is stricter. Let's use distinct placeholders.
                query_builder.push_str(&format!(" AND (title LIKE ?{0} OR content LIKE ?{1})", arg_idx, arg_idx + 1));
                let pattern = format!("%{}%", search_term);
                bindings.push(pattern.clone().into());
                bindings.push(pattern.into());
                arg_idx += 2;
            }
        }

        query_builder.push_str(" ORDER BY updatedAt DESC");

        let limit_val = params.limit.unwrap_or(20);
        query_builder.push_str(&format!(" LIMIT ?{}", arg_idx));
        bindings.push(limit_val.into());
        arg_idx += 1;

        if let Some(offset) = params.offset {
             query_builder.push_str(&format!(" OFFSET ?{}", arg_idx));
            bindings.push(offset.into());
            // arg_idx += 1; // No more params after this one in this construction
        }

        console_log!("Executing get_notes SQL: {} with bindings count: {}", query_builder, bindings.len());

        let statement = db.prepare(&query_builder).bind(&bindings)?;
        let d1_notes_result = statement.all().await?;

        Ok(d1_notes_result.results::<NoteFromD1>()?
            .into_iter()
            .map(Note::from)
            .collect())
    }

    async fn get_note(&self, ctx: Context, id: String) -> Result<Option<Note>> {
        let db = ctx.env.d1("DB")?;
        let user_id = "user-1";

        let statement = db.prepare("SELECT id, userId, title, content, tags, favorite, archived, createdAt, updatedAt FROM notes WHERE id = ?1 AND userId = ?2")
            .bind(&[id.into(), user_id.into()])?;

        let d1_note_result: Option<NoteFromD1> = statement.first(None).await?;
        Ok(d1_note_result.map(Note::from))
    }

    async fn update_note(&self, ctx: Context, id: String, input: UpdateNoteInput) -> Result<Note> {
        let db = ctx.env.d1("DB")?;
        let user_id = "user-1";
        let now_ts = Utc::now().to_rfc3339();

        let check_stmt = db.prepare("SELECT id FROM notes WHERE id = ?1 AND userId = ?2")
            .bind(&[id.clone().into(), user_id.into()])?;
        if check_stmt.first::<serde_json::Value>(None).await?.is_none() { // Using serde_json::Value as a generic placeholder
            return Err(worker::Error::RustError("Note not found or access denied".to_string()));
        }

        let mut set_clauses = Vec::new();
        let mut bindings: Vec<worker::query::QueryArgument> = Vec::new();
        let mut arg_idx = 1;

        if let Some(title) = input.title {
            set_clauses.push(format!("title = ?{}", arg_idx));
            bindings.push(title.into());
            arg_idx += 1;
        }
        if let Some(content) = input.content {
            set_clauses.push(format!("content = ?{}", arg_idx));
            bindings.push(content.into());
            arg_idx += 1;
        }
        if let Some(tags) = input.tags {
            let tags_json = serde_json::to_string(&tags)
                .map_err(|e| worker::Error::RustError(format!("Failed to serialize tags: {}", e)))?;
            set_clauses.push(format!("tags = ?{}", arg_idx));
            bindings.push(tags_json.into());
            arg_idx += 1;
        }
        if let Some(favorite) = input.favorite {
            set_clauses.push(format!("favorite = ?{}", arg_idx));
            bindings.push((if favorite { 1 } else { 0 }).into());
            arg_idx += 1;
        }
        if let Some(archived) = input.archived {
            set_clauses.push(format!("archived = ?{}", arg_idx));
            bindings.push((if archived { 1 } else { 0 }).into());
            arg_idx += 1;
        }

        if set_clauses.is_empty() {
            return self.get_note(ctx, id).await?.ok_or_else(|| worker::Error::RustError("Note not found after empty update".to_string()));
        }

        set_clauses.push(format!("updatedAt = ?{}", arg_idx));
        bindings.push(now_ts.into());
        arg_idx += 1;

        let where_id_idx = arg_idx;
        let where_user_id_idx = arg_idx + 1;
        bindings.push(id.clone().into());
        bindings.push(user_id.into());

        let query = format!(
            "UPDATE notes SET {} WHERE id = ?{} AND userId = ?{}",
            set_clauses.join(", "),
            where_id_idx,
            where_user_id_idx
        );

        console_log!("Executing update_note SQL: {} with bindings count: {}", query, bindings.len());

        let statement = db.prepare(&query).bind(&bindings)?;
        statement.run().await?;

        self.get_note(ctx, id).await?.ok_or_else(|| worker::Error::RustError("Failed to retrieve updated note".to_string()))
    }

    async fn delete_note(&self, ctx: Context, id: String) -> Result<String> {
        let db = ctx.env.d1("DB")?;
        let user_id = "user-1";

        let check_stmt = db.prepare("SELECT id FROM notes WHERE id = ?1 AND userId = ?2")
            .bind(&[id.clone().into(), user_id.into()])?;
        if check_stmt.first::<serde_json::Value>(None).await?.is_none() {
            return Err(worker::Error::RustError("Note not found or access denied for deletion".to_string()));
        }

        let statement = db.prepare("DELETE FROM notes WHERE id = ?1 AND userId = ?2")
            .bind(&[id.clone().into(), user_id.into()])?;

        statement.run().await?;

        Ok(format!("Note with id {} deleted successfully", id))
    }
}
