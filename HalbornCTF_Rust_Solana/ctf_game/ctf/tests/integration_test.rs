// Integration tests for the Solana vulnerable game contract
// These tests demonstrate the integer underflow vulnerability in user_level_up

use solana_vulnerable_game::{
    instructions::*,
    state::*,
    constants::*,
    id,
    process_instruction,
};
use solana_program::pubkey::Pubkey;
use solana_program_test::*;
use solana_sdk::{
    account::Account,
    signature::{Keypair, Signer},
    transaction::Transaction,
    native_token::LAMPORTS_PER_SOL,
};
use borsh::BorshSerialize;

#[tokio::test]
async fn test_user_level_up_integer_underflow_vulnerability() {
    // This test demonstrates the critical integer underflow vulnerability
    // in the user_level_up function.
    //
    // Vulnerability: The function subtracts credits BEFORE checking if the user has enough,
    // causing integer underflow when user.credits < level_credits
    
    let program_id = id();
    
    // Initialize ProgramTest and add the program with its processor
    let mut program_test = ProgramTest::default();
    program_test.add_program(
        "solana_vulnerable_game",
        program_id,
        processor!(process_instruction),
    );
    
    // Start the test environment
    let (mut banks_client, payer, recent_blockhash) = program_test.start().await;
    
    // Setup: Create admin and user authority keypairs
    let admin = Keypair::new();
    let user_authority = Keypair::new();
    
    // Derive PDAs
    let (game_config_pubkey, _) = Pubkey::find_program_address(
        &[admin.pubkey().as_ref(), GAME_CONFIG_SEED],
        &program_id
    );
    
    let (user_pubkey, _) = Pubkey::find_program_address(
        &[
            game_config_pubkey.as_ref(),
            user_authority.pubkey().as_ref(),
            USER_SEED
        ],
        &program_id
    );
    
    // Create and initialize game config account
    let credits_per_level: u8 = 10;
    
    // Create the game config account
    let create_game_config_ix = create_game_config(
        game_config_pubkey,
        admin.pubkey(),
        credits_per_level
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[create_game_config_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &admin], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Create user account
    let create_user_ix = create_user(
        game_config_pubkey,
        user_pubkey,
        user_authority.pubkey(),
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[create_user_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &user_authority], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Mint some credits to the user (but not enough for the level up)
    let mint_ix = mint_credits_to_user(
        game_config_pubkey,
        user_pubkey,
        admin.pubkey(),
        5u32 // User has only 5 credits
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[mint_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &admin], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Attack: Try to level up with credits_to_burn = 50
    // This will calculate level_credits = 30 (for level 3)
    // Calculation:
    //   - Starting: iterator=0, level_credits=0, next_level_credits=0
    //   - Iteration 1: level_credits=0, iterator=1, next_level_credits=10
    //   - Iteration 2: level_credits=10, iterator=2, next_level_credits=30
    //   - Iteration 3: level_credits=30, iterator=3, next_level_credits=60
    //   - Loop exits (60 < 50 is false)
    //   - Result: level_credits = 30
    //   - Subtraction: user.credits (5) -= level_credits (30) → UNDERFLOW!
    
    let level_up_ix = user_level_up(
        game_config_pubkey,
        user_pubkey,
        user_authority.pubkey(),
        50u32 // credits_to_burn
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[level_up_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &user_authority], recent_blockhash);
    
    // This should fail due to integer underflow
    let result = banks_client.process_transaction(transaction).await;
    
    // The function should fail because it tries to subtract more credits than the user has
    // In Rust with overflow checks (which Solana programs have), this will panic
    assert!(result.is_err(), "Expected error due to integer underflow");
}

#[tokio::test]
async fn test_user_level_up_validation_after_subtraction_bug() {
    // This test demonstrates that the insufficient funds check happens AFTER subtraction
    // which is a logic error - validation should happen BEFORE state modification
    
    let program_id = id();
    
    // Initialize ProgramTest and add the program with its processor
    let mut program_test = ProgramTest::default();
    program_test.add_program(
        "solana_vulnerable_game",
        program_id,
        processor!(process_instruction),
    );
    
    // Setup: Create admin and user authority keypairs
    let admin = Keypair::new();
    let user_authority = Keypair::new();
    
    // Fund the admin and user_authority accounts
    program_test.add_account(
        admin.pubkey(),
        Account {
            lamports: 10 * LAMPORTS_PER_SOL,
            data: vec![],
            owner: solana_sdk::system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        user_authority.pubkey(),
        Account {
            lamports: 10 * LAMPORTS_PER_SOL,
            data: vec![],
            owner: solana_sdk::system_program::id(),
            executable: false,
            rent_epoch: 0,
        },
    );
    
    // Derive PDAs
    let (game_config_pubkey, _) = Pubkey::find_program_address(
        &[admin.pubkey().as_ref(), GAME_CONFIG_SEED],
        &program_id
    );
    
    let (user_pubkey, _) = Pubkey::find_program_address(
        &[
            game_config_pubkey.as_ref(),
            user_authority.pubkey().as_ref(),
            USER_SEED
        ],
        &program_id
    );
    
    // Pre-create empty PDA accounts owned by the program to avoid PrivilegeEscalation
    // The runtime checks privileges before execution, so accounts must exist
    let rent = solana_sdk::rent::Rent::default();
    program_test.add_account(
        game_config_pubkey,
        Account {
            lamports: rent.minimum_balance(std::mem::size_of::<GameConfig>()),
            data: vec![0u8; std::mem::size_of::<GameConfig>()],
            owner: program_id,
            executable: false,
            rent_epoch: 0,
        },
    );
    program_test.add_account(
        user_pubkey,
        Account {
            lamports: rent.minimum_balance(std::mem::size_of::<User>()),
            data: vec![0u8; std::mem::size_of::<User>()],
            owner: program_id,
            executable: false,
            rent_epoch: 0,
        },
    );
    
    // Start the test environment
    let (mut banks_client, payer, recent_blockhash) = program_test.start().await;
    
    // Create and initialize game config account
    let credits_per_level: u8 = 10;
    
    let create_game_config_ix = create_game_config(
        game_config_pubkey,
        admin.pubkey(),
        credits_per_level
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[create_game_config_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &admin], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Create user account
    let create_user_ix = create_user(
        game_config_pubkey,
        user_pubkey,
        user_authority.pubkey(),
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[create_user_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &user_authority], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Mint exactly enough credits for one level (10 credits for level 0 -> 1)
    let mint_ix = mint_credits_to_user(
        game_config_pubkey,
        user_pubkey,
        admin.pubkey(),
        10u32 // Exactly enough for level 0 -> 1 (1 * 10 = 10)
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[mint_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &admin], recent_blockhash);
    banks_client.process_transaction(transaction).await.unwrap();
    
    // Try to level up with credits_to_burn = 50
    // This will calculate level_credits = 30 (for level 3)
    // user.credits (10) - level_credits (30) = underflow!
    
    let level_up_ix = user_level_up(
        game_config_pubkey,
        user_pubkey,
        user_authority.pubkey(),
        50u32
    );
    
    let mut transaction = Transaction::new_with_payer(
        &[level_up_ix],
        Some(&payer.pubkey()),
    );
    transaction.sign(&[&payer, &user_authority], recent_blockhash);
    
    // Should fail due to underflow - the check happens too late
    let result = banks_client.process_transaction(transaction).await;
    assert!(result.is_err(), "Expected error - validation happens after subtraction");
}
