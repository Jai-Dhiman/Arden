use worker::*;
use worker::rpc::{RpcHandler, RpcMethod};
use serde::{Serialize, Deserialize};
use chrono::{Utc};
use console_error_panic_hook;
use std::panic;
use async_trait::async_trait;

#[derive(Serialize, Deserialize, Clone)]
struct HealthResponse {
    status: String,
    timestamp: String,
    database: String,
    db_check: String,
}

#[derive(Deserialize, Debug)]
struct UserCount {
    count: i32,
}

// Define the RPC service trait
#[async_trait]
pub trait RpcHealthService {
    async fn check_health(&self, ctx: Context) -> Result<HealthResponse>;
}

// Implement the RPC service trait
struct HealthServiceImpl;

#[async_trait]
impl RpcHealthService for HealthServiceImpl {
    async fn check_health(&self, ctx: Context) -> Result<HealthResponse> {
        let d1 = ctx.env.d1("DB")?;
        let statement = d1.prepare("SELECT count(*) as count FROM users");

        // Log the SQL query being executed
        console_log!("Executing SQL: {}", "SELECT count(*) as count FROM users");

        let result: Option<UserCount> = match statement.first(None).await {
            Ok(res) => res,
            Err(e) => {
                console_error!("Database query failed: {}", e);
                return Err(e.into());
            }
        };

        console_log!("Query result: {:?}", result);

        let db_check = match result {
            Some(user_count) if user_count.count > 0 => "records exist".to_string(),
            Some(_) => "no records".to_string(),
            None => "no records".to_string(),
        };

        Ok(HealthResponse {
            status: "ok".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            database: "connected".to_string(),
            db_check,
        })
    }
}

impl RpcMethod for HealthServiceImpl {
    type Signature = dyn RpcHealthService; // Points to the trait
    type Context = Context; // Worker execution context
}


#[event(fetch)]
async fn main(req: Request, env: Env, ctx: Context) -> Result<Response> {
    panic::set_hook(Box::new(console_error_panic_hook::hook));

    let mut rpc_handler = RpcHandler::new();
    rpc_handler.add_service(HealthServiceImpl);

    // If the request is for an RPC call, handle it.
    // Otherwise, you might want to return a 404 or handle other non-RPC routes.
    if req.headers().get("content-type")?.unwrap_or_default() == "application/rpc" {
        return rpc_handler.handle(req, ctx).await;
    }

    // Fallback for non-RPC requests (e.g. if you still want an HTTP health endpoint)
    // For now, let's just return a simple message for non-RPC calls to the root.
    // We've removed the explicit /health HTTP endpoint in favor of RPC.
    if req.path() == "/" {
        Response::ok("Rust RPC Worker is running. Use RPC to call services.")
    } else {
        Response::error("Not Found", 404)
    }
}
