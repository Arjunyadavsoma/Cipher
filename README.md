# Cipher

<p align="center">
  <img src="assets/images/logo.png" width="140" alt="Cipher Logo">
</p>

<p align="center">
  <strong>An AI-first productivity platform with autonomous agents, multi-modal chat, research assistance, automation, and extensible tool orchestration.</strong>
</p>

<p align="center">
  Flutter • Firebase • Supabase • Groq • Riverpod • Clean Architecture
</p>

---

## Overview

Cipher is an intelligent AI workspace designed around autonomous AI agents rather than a traditional chatbot.

Instead of sending every request to a single LLM, Cipher analyzes user intent, routes requests to specialized agents, equips those agents with appropriate tools, executes workflows, and returns structured results.

The platform is built to support future expansion by allowing new agents and tools to be added without changing the core architecture.

---

## Features

### AI Chat

- Multi-turn conversations
- Context-aware responses
- Persistent conversation history
- Streaming AI responses
- Markdown support
- Agent routing
- Tool execution

---

### AI Agent System

Current specialized agents include:

- Research Agent
- RSS News Agent
- Email Agent
- General Assistant

The architecture allows unlimited custom agents.

---

### Research Agent

Professional academic research assistant capable of:

- Paper analysis
- Literature search
- Related work discovery
- Research gap identification
- Future research suggestions
- Academic summarization

Supports multiple providers with fallback routing:

```
Semantic Scholar
        ↓
     Crossref
        ↓
       arXiv
        ↓
        Groq
```

---

### Email Agent

- Draft emails
- Search inbox
- Email summarization
- Follow-up generation
- Context-aware conversations

---

### RSS News Agent

- Latest news
- Category filtering
- Topic summarization
- Daily news brief
- Source aggregation

---

### Authentication

- Email & Password
- Google Sign-In
- Password Reset
- Secure authentication
- Firebase Authentication

---

### User Profiles

- Profile management
- Avatar upload
- Cloud synchronization
- Account settings

---

### Notifications

- Firebase Cloud Messaging
- Push notifications
- Background notifications

---

### Cloud Storage

Uses:

- Firebase
- Firestore
- Supabase Storage

---

### Modern UI

- Material 3
- Responsive layout
- Dark mode ready
- Clean animations
- Professional design

---

## Architecture

Cipher follows a modular Clean Architecture.

```
Presentation Layer
        │
        ▼
Application Layer
        │
        ▼
Agent Router
        │
        ▼
Selected Agent
        │
        ▼
Tool Manager
        │
        ▼
External APIs
```

---

## AI Execution Flow

```
User

   │

   ▼

Chat UI

   │

   ▼

Agent Router

   │

   ▼

Intent Classification

   │

   ▼

Research Agent
Email Agent
RSS Agent
General Agent

   │

   ▼

Tool Manager

   │

   ▼

Research Tool
Groq Tool
Email Tool
RSS Tool

   │

   ▼

API Providers

   │

   ▼

Response
```

---

## Technology Stack

### Frontend

- Flutter
- Dart

### State Management

- Riverpod

### Backend

- Firebase

### Database

- Cloud Firestore

### Authentication

- Firebase Authentication

### Storage

- Supabase Storage

### AI

- Groq API

### HTTP

- http

### Routing

- GoRouter

---

## Folder Structure

```
lib/

├── app/
├── core/
│   ├── services/
│   ├── utils/
│   ├── routing/
│   ├── storage/
│   └── config/
│
├── features/
│   ├── agents/
│   ├── auth/
│   ├── chat/
│   ├── profile/
│   ├── rss/
│   └── research/
│
└── main.dart
```

---

## Supported AI Tools

| Tool | Purpose |
|-------|----------|
| Groq Tool | LLM inference |
| Research Tool | Academic research |
| RSS Tool | News aggregation |
| Email Tool | Email automation |

---

## Installation

### Clone

```bash
git clone https://github.com/Arjunyadavsoma/Cipher.git
```

### Enter project

```bash
cd Cipher
```

### Install dependencies

```bash
flutter pub get
```

### Configure environment

Create a `.env` file.

```env
GROQ_API_KEY=

SUPABASE_URL=

SUPABASE_ANON_KEY=

FIREBASE_PROJECT_ID=
```

---

### Run

```bash
flutter run
```

---

### Release Build

```bash
flutter build apk --release
```

APK output:

```
build/app/outputs/flutter-apk/app-release.apk
```

---

## Security

Cipher never stores sensitive credentials inside source code.

Secrets should always be provided through environment variables or secure configuration.

Examples include:

- API Keys
- Firebase credentials
- Supabase credentials
- OAuth secrets

---

## Roadmap

- Voice assistant
- Vision model integration
- Image generation
- Workflow automation
- Calendar agent
- File agent
- Coding agent
- Memory engine
- Knowledge base
- Vector search
- RAG support
- Plugin ecosystem
- Multi-agent collaboration

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a Pull Request

---

## License

This project is licensed under the MIT License.

---

## Author

**Arjun Yadav**

GitHub: https://github.com/Arjunyadavsoma

---

<p align="center">
Built with Flutter, Firebase, Supabase, and AI.
</p>
