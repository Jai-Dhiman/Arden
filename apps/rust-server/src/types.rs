use serde::{Serialize, Deserialize};
// Removed: use worker::Env; as it's not used directly in this file anymore

// Consistent with packages/core/types/index.ts
// Note: chrono::DateTime<Utc> will be used for timestamps and serialized to RFC3339 strings.

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: String,
    pub user_id: String,
    pub title: String,
    pub content: String,
    pub tags: Vec<String>,
    pub archived: bool,
    pub favorite: bool,
    pub created_at: String, // ISO 8601 string
    pub updated_at: String, // ISO 8601 string
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct CreateNoteInput {
    pub title: String,
    pub content: String,
    #[serde(default = "Vec::new")]
    pub tags: Vec<String>,
    #[serde(default)] // Defaults to false
    pub favorite: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct UpdateNoteInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub favorite: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub archived: Option<bool>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct NotesQueryParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub search: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub archived: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub favorite: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i32>,
}

#[derive(Deserialize, Debug)]
pub struct NoteFromD1 {
    pub id: String,
    #[serde(rename = "userId")]
    pub user_id: String,
    pub title: String,
    pub content: String,
    pub tags: Option<String>,
    pub archived: i32,
    pub favorite: i32,
    #[serde(rename = "createdAt")]
    pub created_at: String,
    #[serde(rename = "updatedAt")]
    pub updated_at: String,
}

impl From<NoteFromD1> for Note {
    fn from(d1_note: NoteFromD1) -> Self {
        Note {
            id: d1_note.id,
            user_id: d1_note.user_id,
            title: d1_note.title,
            content: d1_note.content,
            tags: d1_note.tags.map_or_else(Vec::new, |s| serde_json::from_str(&s).unwrap_or_else(|_| Vec::new())),
            archived: d1_note.archived != 0,
            favorite: d1_note.favorite != 0,
            created_at: d1_note.created_at,
            updated_at: d1_note.updated_at,
        }
    }
}

// Health Check related types
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub status: String,
    pub timestamp: String,
    pub database: String,
    pub db_check: String,
}

#[derive(Deserialize, Debug)]
pub struct UserCount { // Renamed from UserCount to avoid conflict if there's a User struct later
    pub count: i32,
}
