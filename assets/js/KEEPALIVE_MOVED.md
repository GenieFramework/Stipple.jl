# Keepalive.js Has Moved

**As of June 2026**, the keepalive functionality has been moved from Stipple to Genie core.

## Location

The keepalive implementation is now at:
```
/Users/M136270/.julia/dev/Genie/assets/js/keepalive.js
```

## Why?

Keepalive is a core WebChannel feature, not specific to Stipple. Moving it to Genie:
- Makes it available to ALL Genie WebChannel applications
- Improves separation of concerns (transport layer vs UI layer)
- Reduces code duplication
- Centralizes WebSocket health monitoring

## Migration

**No action needed!**

- Stipple automatically inherits keepalive from Genie
- All existing Stipple apps continue to work
- `isModelAlive()` is still available (alias for `isChannelAlive()`)

## For Non-Stipple Apps

If you're building a pure Genie WebChannel app, you now get keepalive for free:

```julia
# Just implement a keepalive route handler
channel("/myapp/keepalive") do
  Dict(
    "channel" => "myapp",
    "message" => "keepalive",
    "payload" => Dict("timestamp" => now())
  ) |> json
end
```

## Documentation

See the main documentation files:
- `/Users/M136270/.julia/merck/KEEPALIVE_PONG_IMPLEMENTATION.md`
- `/Users/M136270/.julia/merck/REFACTORING_SUMMARY.md`

## Git History

If you need the old Stipple-specific version, it's available in git history before June 2026.
