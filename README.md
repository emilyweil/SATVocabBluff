# Vocab Bluff 🎭

A Balderdash-style vocabulary game where friends try to fool each other with fake definitions.

## How It Works

1. **Create or join a group** with friends using an invite code
2. **New round starts** — one person gets the real definition, everyone else makes up fakes
3. **Submit definitions** — the truth-holder rewrites the real definition, others bluff
4. **Vote** — everyone guesses which definition is real
5. **Score points** — 2 pts for fooling someone, 1 pt for guessing correctly

## Setup

### 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Click "New Project" and give it a name
3. Wait for the project to be created (~2 minutes)

### 2. Set Up the Database

1. In your Supabase dashboard, go to **SQL Editor**
2. Click "New Query"
3. Copy the entire contents of `supabase-schema.sql` and paste it
4. Click "Run" — this creates all tables, security rules, and seed vocabulary

### 3. Enable Email Auth

1. Go to **Authentication** → **Providers**
2. Make sure "Email" is enabled
3. For testing, you can disable "Confirm email" in **Authentication** → **Settings**

### 4. Get Your API Keys

1. Go to **Settings** → **API**
2. Copy your **Project URL** (looks like `https://xxxxx.supabase.co`)
3. Copy your **anon/public** key

### 5. Configure the App

Open `index.html` and find these lines near the top:

```javascript
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```

Replace with your actual values:

```javascript
const SUPABASE_URL = 'https://xxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGc...your-key-here';
```

### 6. Deploy to Vercel

**Option A: Drag & Drop**
1. Go to [vercel.com](https://vercel.com) and sign up
2. From your dashboard, drag the `vocab-bluff` folder onto the page
3. Done! You'll get a URL like `vocab-bluff-xxx.vercel.app`

**Option B: CLI**
```bash
npm i -g vercel
cd vocab-bluff
vercel
```

**Option C: GitHub**
1. Push this folder to a GitHub repo
2. Connect the repo to Vercel
3. It auto-deploys on every push

## Playing the Game

1. **Create an account** — just email + password
2. **Create a group** — you'll get a 6-character invite code
3. **Share the code** — friends join with the code
4. **Start a round** — tap "Start New Round"
5. **Submit definitions** — one person gets the real one (marked with 🎯)
6. **Vote** — pick which definition you think is real
7. **See results** — find out who fooled who!

## Files

- `index.html` — The entire app (React + Supabase, loaded from CDN)
- `supabase-schema.sql` — Database setup script (run once in Supabase)
- `README.md` — This file

## Scoring

| Action | Points |
|--------|--------|
| Fool someone with your fake definition | +2 |
| Correctly guess the real definition | +1 |

The leaderboard shows total points, plus breakdowns of 🎭 (fools) and ✓ (correct guesses).
# SATVocabBluff
