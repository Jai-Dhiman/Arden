use worker::*;
use worker::rpc::{RpcHandler, RpcMethod};
// Serde, Chrono, etc. are used within services/types modules
use console_error_panic_hook;
use std::panic;
// async-trait is used within services module

// Modules
mod types;
mod services;

// Use services and their traits. Specific types are used within services.
use services::{
    HealthServiceImpl, RpcHealthService,
    NotesServiceImpl, RpcNotesService,
};

// RpcMethod implementations tell the RpcHandler how to call the service methods.
impl RpcMethod for HealthServiceImpl {
    type Signature = dyn RpcHealthService;
    type Context = Context;
}

impl RpcMethod for NotesServiceImpl {
    type Signature = dyn RpcNotesService;
    type Context = Context;
}

#[event(fetch)]
async fn main(req: Request, _env: Env, ctx: Context) -> Result<Response> { // env is not directly used here now
    panic::set_hook(Box::new(console_error_panic_hook::hook));

    let mut rpc_handler = RpcHandler::new();
    rpc_handler.add_service(HealthServiceImpl);
    rpc_handler.add_service(NotesServiceImpl);

    // Check if it's an RPC call
    if req.headers().get("content-type")?.map_or(false, |ct| ct == "application/rpc") {
        return rpc_handler.handle(req, ctx).await;
    }

    // Fallback for non-RPC requests
    if req.path() == "/" {
        Response::ok("Rust RPC Worker is running. Available services: Health, Notes.")
    } else {
        Response::error("Not Found", 404)
    }
}
