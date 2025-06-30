import type {
  Note,
  CreateNoteInput,
  UpdateNoteInput,
  NotesQueryParams,
  NotesResponse, // This will become Vec<Note> essentially
  NoteResponse,  // This will become Note or Option<Note>
} from '../types';

// Base API URL for the Rust RPC worker.
// This might be different from the original TS server's /api path.
// The Rust worker handles RPC calls at its root.
const RPC_API_BASE_URL = 'http://localhost:8787'; // Assuming it runs on the same port for now

// Helper function to make RPC requests to the Rust worker
async function rpcRequest<T>(service: string, method: string, params: unknown[]): Promise<T> {
  const response = await fetch(RPC_API_BASE_URL, { // POST to the root of the worker
    method: 'POST',
    headers: {
      'Content-Type': 'application/rpc', // Specific content type for workers-rpc
    },
    body: JSON.stringify({
      service,
      method,
      params,
    }),
  });

  if (!response.ok) {
    // Try to parse error from server if available
    let errorPayload;
    try {
      errorPayload = await response.json();
    } catch (e) {
      // Ignore parsing error, use status text
    }
    const errorMessage = errorPayload?.error?.message || errorPayload?.error || response.statusText || `RPC Error: ${response.status}`;
    console.error('RPC Request Failed:', { service, method, params, status: response.status, error: errorMessage });
    throw new Error(errorMessage);
  }

  const result = await response.json();
  // workers-rpc wraps successful results in an "Ok" field and errors in an "Err" field.
  // Need to unwrap this.
  if (result.Ok !== undefined) {
    return result.Ok as T;
  } else if (result.Err !== undefined) {
    console.error('RPC Method Error:', { service, method, params, error: result.Err });
    // The error structure from Rust might be { code: ..., message: ... } or just a string
    const errMessage = typeof result.Err === 'object' && result.Err.message ? result.Err.message : JSON.stringify(result.Err);
    throw new Error(errMessage);
  } else {
    // Should not happen if server follows workers-rpc conventions
    console.error('Unexpected RPC response format:', result);
    throw new Error('Unexpected RPC response format');
  }
}

// Notes API functions using Rust RPC
export const notesApi = {
  // Get all notes
  // Rust: get_notes(ctx: Context, params: NotesQueryParams) -> Result<Vec<Note>>
  // TS Expected: Promise<{ notes: Array<Note> }> (to match existing NotesResponse)
  getNotes: async (params?: NotesQueryParams): Promise<NotesResponse> => {
    // The RpcNotesService.get_notes expects params as the second argument.
    // The Context is handled server-side.
    const notesArray = await rpcRequest<Array<Note>>('NotesServiceImpl', 'get_notes', [params || {}]);
    return { notes: notesArray }; // Wrap to match existing NotesResponse structure
  },

  // Get a specific note
  // Rust: get_note(ctx: Context, id: String) -> Result<Option<Note>>
  // TS Expected: Promise<{ note: Note | null }> (to match existing NoteResponse, allowing for null if not found)
  getNote: async (id: string): Promise<NoteResponse> => {
    const noteOption = await rpcRequest<Note | null>('NotesServiceImpl', 'get_note', [id]);
    if (!noteOption) {
      // To align with how HTTP 404s were handled (throwing an error),
      // or you could return { note: null } and let the hook/component handle it.
      // For now, let's throw, as the original apiRequest would have from a 404.
      // However, the Rust service returns Option<Note>, so null is a valid "not found"
      // Let's return { note: null } to represent not found, which is cleaner for RPC Option types.
      return { note: null as any }; // Cast to allow null with current NoteResponse
    }
    return { note: noteOption };
  },

  // Create a new note
  // Rust: create_note(ctx: Context, input: CreateNoteInput) -> Result<Note>
  // TS Expected: Promise<{ note: Note }>
  createNote: async (input: CreateNoteInput): Promise<NoteResponse> => {
    const newNote = await rpcRequest<Note>('NotesServiceImpl', 'create_note', [input]);
    return { note: newNote };
  },

  // Update a note
  // Rust: update_note(ctx: Context, id: String, input: UpdateNoteInput) -> Result<Note>
  // TS Expected: Promise<{ note: Note }>
  updateNote: async (id: string, input: UpdateNoteInput): Promise<NoteResponse> => {
    const updatedNote = await rpcRequest<Note>('NotesServiceImpl', 'update_note', [id, input]);
    return { note: updatedNote };
  },

  // Delete a note
  // Rust: delete_note(ctx: Context, id: String) -> Result<String> (message)
  // TS Expected: Promise<{ message: string }>
  deleteNote: async (id: string): Promise<{ message: string }> => {
    const message = await rpcRequest<string>('NotesServiceImpl', 'delete_note', [id]);
    return { message };
  },
};
