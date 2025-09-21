# Artion Tipping Contract

A secure Clarity smart contract for time-locked STX token tips on the Stacks blockchain.

## Features

- **Secure Tipping**: Send STX tokens with customizable time locks
- **Claim System**: Recipients can claim tips after unlock period
- **Emergency Recovery**: Original tippers can recover unclaimed funds after ~100 days
- **Transparent Status**: Multiple read functions for checking tip status

## Core Functions

### Public Functions
- `tip`: Create new time-locked tips
- `claim`: Claim unlocked tips (recipient only)
- `emergency-withdraw`: Recover unclaimed tips (original tipper only)

### Read-Only Functions
- `get-tip`: Get tip details
- `get-next-tip-id`: View next available tip ID
- `get-tip-status`: Check tip status including unlock time
- `can-claim-tip`: Verify if user can claim tip
- `get-contract-balance`: View contract's STX balance

## Security Features

- Input validation for amounts and lock periods
- Principal-based authorization
- Protection against self-tipping
- Safe STX transfer handling
- Time-lock enforcement
- Emergency withdrawal timeout

## Error Handling

Comprehensive error codes for:
- Invalid inputs (`u100-u102`)
- State errors (`u200-u203`)
- Transfer failures (`u300`)
- Emergency withdrawal issues (`u400`)

## Data Structure

Uses a map to store tips with:
- Tipper principal
- Recipient principal
- Amount in STX
- Unlock height
- Claim status

## Constants
- Emergency timeout: 144000 blocks (~100 days)
