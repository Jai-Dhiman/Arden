use reqwest::Client;
use serde::{Serialize, Deserialize};
use anyhow::{Result, Context, bail}; // Using anyhow for error handling

const MCP_SERVER_URL: &str = "http://localhost:27123"; // Default for Obsidian Local REST API

#[derive(Debug, Serialize, Deserialize)]
struct Frontmatter {
    // Define common frontmatter fields
    tags: Option<Vec<String>>,
    due_date: Option<String>,
    // Add other fields as needed
}

#[derive(Debug, Serialize, Deserialize)]
struct MarkdownFile {
    frontmatter: Frontmatter,
    content: String,
}

pub struct ObsidianAdapter {
    client: Client,
    base_url: String,
}

impl ObsidianAdapter {
    pub fn new(base_url: Option<String>) -> Self {
        ObsidianAdapter {
            client: Client::new(),
            base_url: base_url.unwrap_or_else(|| MCP_SERVER_URL.to_string()),
        }
    }

    fn parse_markdown_file(raw_content: &str) -> Result<MarkdownFile> {
        // Basic parsing: assumes frontmatter is at the beginning, enclosed by "---"
        // and content is everything after the second "---"
        // A more robust parser would be needed for complex cases or malformed files.

        let parts: Vec<&str> = raw_content.splitn(3, "---").collect();
        if parts.len() < 3 {
            // No frontmatter or malformed
            return Ok(MarkdownFile {
                frontmatter: Frontmatter { tags: None, due_date: None }, // Default empty frontmatter
                content: raw_content.to_string(),
            });
        }

        let yaml_str = parts[1].trim();
        let content_str = parts[2].trim_start().to_string();

        let frontmatter: Frontmatter = serde_yaml::from_str(yaml_str)
            .context("Failed to parse YAML frontmatter")?;

        Ok(MarkdownFile {
            frontmatter,
            content: content_str,
        })
    }

    fn serialize_markdown_file(file: &MarkdownFile) -> Result<String> {
        let fm_yaml = serde_yaml::to_string(&file.frontmatter)
            .context("Failed to serialize frontmatter to YAML")?;
        Ok(format!("---\n{}---\n\n{}", fm_yaml.trim(), file.content))
    }

    pub async fn get_file(&self, vault_path: &str) -> Result<String> {
        // vault_path should be relative to the vault root, e.g., "todos/my-task.md"
        // The Local REST API plugin uses GET /vault/path/to/file.md (raw content)
        let url = format!("{}/vault/{}", self.base_url, vault_path);

        let response = self.client.get(&url)
            .header("Accept", "text/markdown") // Or "application/json" for metadata if API supports
            .send()
            .await
            .context(format!("Failed to send GET request to {}", url))?;

        if response.status().is_success() {
            response.text().await.context("Failed to read response text")
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            bail!("MCP server returned error {}: {}", status, error_text)
        }
    }

    pub async fn create_file(&self, vault_path: &str, content: &str) -> Result<()> {
        // The Local REST API plugin uses POST /vault/path/to/file.md with raw content in body
        let url = format!("{}/vault/{}", self.base_url, vault_path);

        let response = self.client.post(&url)
            .header("Content-Type", "text/markdown")
            .body(content.to_string()) // reqwest::Body can take String
            .send()
            .await
            .context(format!("Failed to send POST request to {}", url))?;

        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            bail!("MCP server returned error {}: {}", status, error_text)
        }
    }

    pub async fn update_file(&self, vault_path: &str, content: &str) -> Result<()> {
        // The Local REST API plugin uses PUT /vault/path/to/file.md with raw content in body to overwrite
        // Or PATCH for partial updates if the API supports it (e.g. with specific headers)
        // For simplicity, we'll use PUT to overwrite, which is similar to create but for existing files.
        let url = format!("{}/vault/{}", self.base_url, vault_path);

        let response = self.client.put(&url)
            .header("Content-Type", "text/markdown")
            .body(content.to_string())
            .send()
            .await
            .context(format!("Failed to send PUT request to {}", url))?;

        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            bail!("MCP server returned error {}: {}", status, error_text)
        }
    }

    // Example of a higher-level function using the parser/serializer
    pub async fn get_markdown_file_data(&self, vault_path: &str) -> Result<MarkdownFile> {
        let raw_content = self.get_file(vault_path).await?;
        Self::parse_markdown_file(&raw_content)
    }

    pub async fn save_markdown_file_data(&self, vault_path: &str, file_data: &MarkdownFile, overwrite: bool) -> Result<()> {
        let serialized_content = Self::serialize_markdown_file(file_data)?;
        if overwrite {
            self.update_file(vault_path, &serialized_content).await
        } else {
            // This assumes create_file will fail if the file exists.
            // The Obsidian Local REST API's POST /vault/path will create or overwrite.
            // So, for this API, create_file and update_file might be quite similar.
            // Let's make `create_file` effectively an upsert for now.
            self.create_file(vault_path, &serialized_content).await
        }
    }
}

// Basic tests (would need a running mock server or actual MCP server to run fully)
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_markdown_with_frontmatter() {
        let raw_md = r#"---
tags: [test, example]
due_date: "2024-01-01"
---

This is the content."#;
        let parsed = ObsidianAdapter::parse_markdown_file(raw_md).unwrap();
        assert_eq!(parsed.content, "This is the content.");
        assert_eq!(parsed.frontmatter.tags, Some(vec!["test".to_string(), "example".to_string()]));
        assert_eq!(parsed.frontmatter.due_date, Some("2024-01-01".to_string()));
    }

    #[test]
    fn test_parse_markdown_without_frontmatter() {
        let raw_md = "Just content here.";
        let parsed = ObsidianAdapter::parse_markdown_file(raw_md).unwrap();
        assert_eq!(parsed.content, "Just content here.");
        assert!(parsed.frontmatter.tags.is_none());
    }

    #[test]
    fn test_parse_markdown_empty_frontmatter() {
        let raw_md = r#"---
---

Content below empty frontmatter."#;
        let parsed = ObsidianAdapter::parse_markdown_file(raw_md).unwrap();
        assert_eq!(parsed.content, "Content below empty frontmatter.");
        assert!(parsed.frontmatter.tags.is_none()); // Assuming empty frontmatter means None for specific fields
    }

    #[test]
    fn test_serialize_markdown_file() {
        let file_data = MarkdownFile {
            frontmatter: Frontmatter {
                tags: Some(vec!["rust".to_string(), "dev".to_string()]),
                due_date: Some("tomorrow".to_string()),
            },
            content: "Writing some Rust code.".to_string(),
        };
        let serialized = ObsidianAdapter::serialize_markdown_file(&file_data).unwrap();
        let expected_fm_yaml = "tags:\n- rust\n- dev\ndue_date: tomorrow";
        let expected_output = format!("---\n{}---\n\nWriting some Rust code.", expected_fm_yaml);
        assert_eq!(serialized.trim(), expected_output.trim());
    }

    // Tokio tests for async functions would go here, likely requiring a mock HTTP server.
    // For example:
    // #[tokio::test]
    // async fn test_get_file_mocked() {
    //     // Setup mock server
    //     let adapter = ObsidianAdapter::new(Some("mock_server_url".to_string()));
    //     // adapter.get_file("test.md").await ...
    // }
}
