# BTC Guess Game 🪙

A real-time Bitcoin price guessing game built with Phoenix LiveView. Players guess whether the BTC/USD price will go up or down in the next 60 seconds.

## Features

- ✅ **Real-time BTC price updates** via WebSocket (Coinbase API)
- ✅ **Live countdown timer** showing time remaining
- ✅ **Persistent player sessions** (cookie-based, 5-year expiry)
- ✅ **Score tracking** (+1 for wins, -1 for losses)
- ✅ **Guess history** showing last 5 rounds
- ✅ **Background job processing** with Oban
- ✅ **Atomic score updates** with pessimistic locking
- ✅ **Beautiful, responsive UI** with Tailwind CSS

## Tech Stack

- **Phoenix 1.8** - Web framework
- **LiveView** - Real-time UI updates
- **Oban** - Background job processing
- **PostgreSQL** - Database
- **WebSockex** - WebSocket client for price streaming
- **Finch** - HTTP client for REST API fallback
- **Tailwind CSS** - Styling

## Local Development

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 27+
- PostgreSQL 14+

## Docker Deployment

### Quick Start (Recommended)

```bash
# One-command setup with health checks
./docker-start.sh
```

The script will:

- ✅ Build Docker images
- ✅ Start PostgreSQL and Phoenix services
- ✅ Run database migrations automatically
- ✅ Verify services are healthy
- ✅ Show you the app URL and useful commands

**App available at:** `http://localhost:4000`

### Manual Docker Compose

```bash
# Build and start services
docker-compose up --build

# Run in detached mode
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down

# Clean up volumes
docker-compose down -v
```

### Using Docker Only

```bash
# Build the image
docker build -t btc_guess .

# Run PostgreSQL
docker run -d \
  --name btc_guess_db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=btc_guess_dev \
  -p 5432:5432 \
  postgres:16-alpine

# Run the app
docker run -d \
  --name btc_guess_app \
  -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/btc_guess_dev \
  -e SECRET_KEY_BASE=your-secret-key-base-at-least-64-chars \
  -e PHX_HOST=localhost \
  -p 4000:4000 \
  btc_guess
```

## Environment Variables

| Variable          | Description                    | Default                                            |
| ----------------- | ------------------------------ | -------------------------------------------------- |
| `DATABASE_URL`    | PostgreSQL connection string   | `ecto://postgres:postgres@localhost/btc_guess_dev` |
| `SECRET_KEY_BASE` | Phoenix secret key (64+ chars) | Generated in dev                                   |
| `PHX_HOST`        | Hostname for URLs              | `localhost`                                        |
| `PORT`            | HTTP port                      | `4000`                                             |

### Setup

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server

# Or start with IEx
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

### Run Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/btc_guess/guesses_test.exs

# Run with coverage
mix test --cover
```

## How It Works

### Game Flow

1. **Player visits** → Cookie created with UUID
2. **Player guesses** "UP" or "DOWN"
3. **Entry price recorded** from live WebSocket feed
4. **60-second countdown** starts
5. **Background job resolves** guess after 60s
6. **Score updated** atomically (+1 win, -1 loss)
7. **LiveView updates** UI via PubSub

### Architecture

```
┌─────────────────┐
│ Coinbase WS API │
└────────┬────────┘
         │ Real-time price updates
         ▼
┌──────────────────┐
│ Price.Streamer   │ ◄── Single WebSocket connection
└────────┬─────────┘
         │
         ├─► Cache (in-memory)
         │
         └─► PubSub.broadcast("price:ticker")
                      │
                      ├─► LiveView (UI updates)
                      └─► Background Jobs (resolution)
```

### Price Resolution

- **Primary**: WebSocket stream (~1 update/second)
- **Fallback**: REST API (if WS down or cache stale)
- **Freshness**: 15-second cache TTL
- **Retry logic**: `ResolveGuessJob` retries if price unchanged

## Edge Cases & Reliability

### Race Conditions Handled

**1. Concurrent Score Updates**

- ✅ **Solution**: Atomic database updates using `Repo.update_all(inc: [score: inc])`
- ✅ **Why**: Multiple jobs resolving simultaneously won't corrupt player scores
- ✅ **Test**: `test/btc_guess/guesses/jobs/resolve_guess_job_test.exs` - "atomic score update prevents race conditions"

**2. Duplicate Guess Prevention**

- ✅ **Solution**: Unique partial index `uniq_open_guess_per_player` on `(player_id) WHERE resolved = false`
- ✅ **Why**: Database enforces one active guess per player
- ✅ **Impact**: Prevents double-betting if user clicks button twice

**3. Pessimistic Locking for Guess Resolution**

- ✅ **Solution**: `SELECT ... FOR UPDATE` in `GuessEligibilityJob`
- ✅ **Why**: Prevents two jobs from resolving the same guess
- ✅ **Flow**: Lock → Check if resolved → Update → Commit

**4. Price Unchanged After 60s**

- ✅ **Solution**: `ResolveGuessJob` reschedules in 5s if `Outcome.evaluate` returns `:no_change`
- ✅ **Why**: Rare but possible with low volatility
- ✅ **Max retries**: 20 attempts (Oban default)

**5. WebSocket Disconnection**

- ✅ **Solution**: Auto-reconnect with exponential backoff (1-5s delay)
- ✅ **Fallback**: REST API used if cache stale (>15s)
- ✅ **Impact**: Jobs continue working even if live UI pauses

**6. Database Connection Loss**

- ✅ **Solution**: Ecto connection pool with automatic retry
- ✅ **Oban**: Jobs automatically retry on DB errors
- ✅ **Config**: `pool_size: 10` with queue management

**7. Stale Price Data**

- ✅ **Solution**: Cache freshness check (15s TTL)
- ✅ **Validation**: Price must be > 0 and valid Decimal
- ✅ **Timestamp**: Both `exchange_ts` and `received_at` tracked

### Data Integrity

**Type Safety**

- ✅ All enums use atoms (`:up`/`:down`, `:win`/`:lose`, `:ws`/`:rest`)
- ✅ Prices stored as `Decimal` (no floating-point errors)
- ✅ UUIDs for player/guess IDs (no collisions)

**Validation**

- ✅ Entry price must exist and be positive
- ✅ Eligibility timestamp = placed_at + 60 seconds
- ✅ Guess can't be resolved before eligibility time

**Idempotency**

- ✅ Jobs check `resolved` flag before processing
- ✅ Migrations can run multiple times safely
- ✅ Player creation uses `ON CONFLICT DO NOTHING`

### Known Limitations

**1. Single WebSocket Connection**

- **Issue**: If streamer crashes, no price updates until restart
- **Mitigation**: Supervisor auto-restarts, REST fallback works
- **Future**: Consider multiple WS connections or external price service

**2. In-Memory Cache Loss**

- **Issue**: Cache cleared on app restart
- **Mitigation**: First request after restart fetches from REST
- **Impact**: Minimal - cache rebuilds in <1 second

**3. Clock Skew**

- **Issue**: Server time vs Coinbase exchange time may differ
- **Mitigation**: Use `received_at` for local timestamps
- **Impact**: Negligible for 60-second windows

**4. No Guess Cancellation**

- **Issue**: Once placed, guess can't be cancelled
- **Reason**: Prevents gaming the system by cancelling losing bets
- **Future**: Could add with penalty (e.g., -2 points)

**5. Price API Rate Limits**

- **Issue**: Coinbase may rate-limit REST requests
- **Mitigation**: WebSocket primary, REST only for fallback
- **Frequency**: REST called only when cache stale or WS down

**6. No Authentication**

- **Issue**: Cookie-based sessions, no user accounts
- **Reason**: Simplicity for demo/MVP
- **Future**: Add OAuth, email login, leaderboards

**7. Score Overflow**

- **Issue**: Integer score could theoretically overflow
- **Mitigation**: PostgreSQL `integer` type supports ±2.1 billion
- **Reality**: Would require 2 billion consecutive wins

### Testing Coverage

- ✅ **Unit Tests**: Outcome evaluation, price validation
- ✅ **Integration Tests**: Job execution, database transactions
- ✅ **Edge Cases**: Race conditions, retries, atomic updates

## Project Structure

```
lib/
├── btc_guess/
│   ├── guesses/           # Core game logic
│   │   ├── jobs/          # Oban background jobs
│   │   └── outcome.ex     # Win/loss evaluation
│   ├── players/           # Player schema
│   ├── price/             # BTC price fetching
│   │   ├── cache.ex       # In-memory price cache
│   │   └── streamer.ex    # WebSocket client
│   └── release.ex         # Production migrations
├── btc_guess_web/
│   ├── live/
│   │   └── game_live.ex   # Main game LiveView
│   └── user_id_plug.ex    # Session management
test/
├── btc_guess/
│   ├── guesses_test.exs
│   ├── guesses/
│   │   ├── outcome_test.exs
│   │   └── jobs/          # Job tests
│   └── ...
```
