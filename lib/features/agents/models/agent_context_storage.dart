/// Determines where a given agent's persistent context lives.
///
/// - [firestore]: small, structured context (e.g. progress notes, preferences)
/// - [supabase]: larger blobs (e.g. accumulated research documents/findings)
/// - [none]: agent has no persistent context beyond the conversation itself
enum AgentContextStorage { firestore, supabase, none }