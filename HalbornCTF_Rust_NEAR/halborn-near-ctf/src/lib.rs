use near_contract_standards::fungible_token::core::FungibleTokenCore;
use near_contract_standards::fungible_token::metadata::{
    FungibleTokenMetadata, FungibleTokenMetadataProvider, FT_METADATA_SPEC,
};
use near_contract_standards::fungible_token::resolver::FungibleTokenResolver;
use near_contract_standards::fungible_token::Balance;
use near_contract_standards::fungible_token::FungibleToken;
use near_contract_standards::storage_management::{
    StorageBalance, StorageBalanceBounds, StorageManagement,
};
use near_sdk::borsh::{BorshDeserialize, BorshSerialize};
use near_sdk::collections::{LazyOption, LookupMap};
use near_sdk::json_types::U128;
use near_sdk::serde::{Deserialize, Serialize};
use near_sdk::{
    env, ext_contract, log, near_bindgen, AccountId, Gas, NearToken, PanicOnDefault, PromiseOrValue,
};
use std::convert::From;

pub const GAS_FOR_REGISTER: Gas = Gas::from_gas(10_000_000_000_000);

#[ext_contract]
pub trait AssociatedContractInterface {
    fn register_for_an_event(&mut self, event_id: U128, account_id: AccountId);
}

#[derive(
    BorshDeserialize, BorshSerialize, Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize,
)]
#[borsh(crate = "near_sdk::borsh")]
#[serde(crate = "near_sdk::serde")]
pub enum BlocklistStatus {
    Allowed,
    Banned,
}

#[derive(
    BorshDeserialize, BorshSerialize, Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize,
)]
#[borsh(crate = "near_sdk::borsh")]
#[serde(crate = "near_sdk::serde")]
pub enum ContractStatus {
    Working,
    Paused,
}

impl std::fmt::Display for ContractStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContractStatus::Working => write!(f, "working"),
            ContractStatus::Paused => write!(f, "paused"),
        }
    }
}

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
#[borsh(crate = "near_sdk::borsh")]
pub struct MalbornClubContract {
    owner_id: AccountId,
    malborn_token: FungibleToken,
    token_metadata: LazyOption<FungibleTokenMetadata>,
    block_list: LookupMap<AccountId, BlocklistStatus>,
    status: ContractStatus,
    associated_contract_account_id: LazyOption<AccountId>,
    registration_fee_denominator: U128,
}

#[near_bindgen]
impl MalbornClubContract {
    #[init]
    pub fn new(owner_id: AccountId, token_total_supply: U128) -> Self {
        assert!(!env::state_exists(), "Already initialized");
        let metadata = FungibleTokenMetadata {
            spec: FT_METADATA_SPEC.to_string(),
            name: "Malborn Token".to_string(),
            symbol: "MAL".to_string(),
            icon: None,
            reference: None,
            reference_hash: None,
            decimals: 10,
        };

        // default registration_fee_denominator results in user burning
        // 0.01% of current total supply to register
        let mut this_state = Self {
            owner_id: owner_id.clone(),
            malborn_token: FungibleToken::new(b"t".to_vec()),
            token_metadata: LazyOption::new(b"m".to_vec(), Some(&metadata)),
            block_list: LookupMap::new(b"b".to_vec()),
            status: ContractStatus::Working,
            associated_contract_account_id: LazyOption::new(b"a".to_vec(), None),
            registration_fee_denominator: U128::from(10000),
        };
        this_state
            .malborn_token
            .internal_register_account(&owner_id);
        this_state
            .malborn_token
            .internal_deposit(&owner_id, token_total_supply.into());
        this_state
    }

    // Mint tokens to someone. Returns the new total_supply
    pub fn mint_tokens(&mut self, account_id: &AccountId, amount: U128) -> Balance {
        self.only_owner();
        self.not_paused();

        self.malborn_token.total_supply = self
            .malborn_token
            .total_supply
            .checked_add(u128::from(amount))
            .expect("Minting caused overflow");

        if let Some(user_amount) = self.malborn_token.accounts.get(account_id) {
            self.malborn_token.accounts.insert(
                account_id,
                &user_amount
                    .checked_add(u128::from(amount))
                    .expect("Exceeded balance"),
            );
        }

        self.malborn_token.total_supply
    }

    // Burn someone's tokens
    pub fn burn_tokens(&mut self, account_id: &AccountId, amount: U128) {
        self.only_owner();
        self.not_paused();
        self.burn_tokens_internal(account_id, amount);
    }

    // Register to an event in the associated contract
    // User, as part of the MalbornClub, can register for burning some of own tokens
    // This is "access to event for the price of influence over MalbornClub" mechanism.
    pub fn register_for_event(&mut self, event_id: U128) {
        self.not_paused();
        assert!(
            self.associated_contract_account_id.is_some(),
            "Associated Account is not set"
        );
        let sender_id = env::signer_account_id();
        self.not_banned(sender_id.clone());

        // burn tokens for registering
        let burn_amount = u128::from(self.malborn_token.total_supply)
            / u128::from(self.registration_fee_denominator);
        self.burn_tokens_internal(&sender_id, U128::from(burn_amount));

        let _ = associated_contract_interface::ext(self.associated_contract_account_id.get().unwrap())
            .with_static_gas(GAS_FOR_REGISTER)
            .register_for_an_event(event_id, sender_id);
    }

    pub fn upgrade_token_name_symbol(&mut self, name: String, symbol: String) {
        self.only_owner();
        let metadata = self.token_metadata.take();
        if let Some(mut metadata) = metadata {
            metadata.name = name;
            metadata.symbol = symbol;
            self.token_metadata.replace(&metadata);
        }
    }

    pub fn add_to_blocklist(&mut self, account_id: &AccountId) {
        self.only_owner();
        self.not_paused();
        self.block_list.insert(account_id, &BlocklistStatus::Banned);
    }

    pub fn remove_from_blocklist(&mut self, account_id: &AccountId) {
        self.only_owner();
        self.not_paused();
        self.block_list
            .insert(account_id, &BlocklistStatus::Allowed);
    }

    pub fn pause(&mut self) {
        self.only_owner();
        self.status = ContractStatus::Paused;
    }

    pub fn resume(&mut self) {
        self.only_owner();
        self.status = ContractStatus::Paused;
    }

    pub fn set_owner(&mut self, new_owner: AccountId) {
        self.only_owner();
        self.owner_id = new_owner;
    }

    pub fn set_registration_fee_denominator(&mut self, new_denominator: U128) {
        self.only_owner();
        self.registration_fee_denominator = new_denominator;
    }

    pub fn set_associated_contract(&mut self, account_id: AccountId) {
        self.only_owner();
        self.associated_contract_account_id.set(&account_id);
    }

    pub fn get_symbol(&mut self) -> String {
        self.not_paused();
        let metadata = self.token_metadata.take();
        metadata
            .expect("Unable to retrieve metadata at this moment")
            .symbol
    }

    pub fn get_name(&mut self) -> String {
        self.not_paused();
        let metadata = self.token_metadata.take();
        metadata
            .expect("Unable to retrieve metadata at this moment")
            .name
    }

    pub fn get_decimals(&mut self) -> u8 {
        self.not_paused();
        let metadata = self.token_metadata.take();
        metadata
            .expect("Unable to retrieve metadata at this moment")
            .decimals
    }

    pub fn contract_status(&self) -> ContractStatus {
        self.status
    }

    pub fn get_blocklist_status(&self, account_id: &AccountId) -> BlocklistStatus {
        self.not_paused();
        return match self.block_list.get(account_id) {
            Some(user_status) => user_status.clone(),
            None => BlocklistStatus::Allowed,
        };
    }

    // **** Helpers ****

    fn burn_tokens_internal(&mut self, account_id: &AccountId, amount: U128) {
        assert!(&self.malborn_token.total_supply >= &Balance::from(amount));
        let user_balance = self
            .malborn_token
            .accounts
            .get(account_id)
            .expect("User not registered");
        assert!(user_balance >= u128::from(amount));

        self.malborn_token.total_supply = self
            .malborn_token
            .total_supply
            .checked_sub(u128::from(amount))
            .expect("Burn caused underflow");

        self.malborn_token.accounts.insert(
            account_id,
            &user_balance
                .checked_sub(u128::from(amount))
                .expect("Underflow in user balance"),
        );
    }

    fn only_owner(&self) {
        if env::signer_account_id() != self.owner_id {
            env::panic_str("Can only be called by owner");
        }
    }

    fn not_paused(&self) {
        if self.status == ContractStatus::Paused {
            env::panic_str("Contract is paused");
        }
    }

    fn not_banned(&self, account_id: AccountId) {
        if self.get_blocklist_status(&account_id) == BlocklistStatus::Banned {
            env::panic_str("User is banned");
        }
    }

    fn on_account_closed(&mut self, account_id: AccountId, balance: Balance) {
        log!("Closed @{} with {}", account_id, balance);
    }
}

#[near_bindgen]
impl FungibleTokenCore for MalbornClubContract {
    #[payable]
    fn ft_transfer(&mut self, receiver_id: AccountId, amount: U128, memo: Option<String>) {
        self.not_paused();
        let sender_id = env::signer_account_id();
        self.not_banned(sender_id.clone());
        assert!(
            u128::from(amount)
                <= u128::from(self.ft_balance_of(sender_id))
        );
        self.malborn_token
            .ft_transfer(receiver_id.clone(), amount, memo);
    }

    #[payable]
    fn ft_transfer_call(
        &mut self,
        receiver_id: AccountId,
        amount: U128,
        memo: Option<String>,
        msg: String,
    ) -> PromiseOrValue<U128> {
        self.not_paused();
        let sender_id = env::signer_account_id();
        self.not_banned(sender_id.clone());
        self.malborn_token
            .ft_transfer_call(receiver_id.clone(), amount, memo, msg)
    }

    fn ft_total_supply(&self) -> U128 {
        self.not_paused();
        self.malborn_token.ft_total_supply()
    }

    fn ft_balance_of(&self, account_id: AccountId) -> U128 {
        self.not_paused();
        self.malborn_token
            .ft_balance_of(account_id)
    }
}

#[near_bindgen]
impl FungibleTokenResolver for MalbornClubContract {
    #[private]
    fn ft_resolve_transfer(
        &mut self,
        sender_id: AccountId,
        receiver_id: AccountId,
        amount: U128,
    ) -> U128 {
        self.malborn_token
            .internal_ft_resolve_transfer(&sender_id, receiver_id, amount)
            .0
            .into()
    }
}

#[near_bindgen]
impl FungibleTokenMetadataProvider for MalbornClubContract {
    fn ft_metadata(&self) -> FungibleTokenMetadata {
        self.token_metadata.get().unwrap()
    }
}

#[near_bindgen]
impl StorageManagement for MalbornClubContract {
    #[payable]
    fn storage_deposit(
        &mut self,
        account_id: Option<AccountId>,
        registration_only: Option<bool>,
    ) -> StorageBalance {
        self.malborn_token
            .storage_deposit(account_id, registration_only)
    }

    #[payable]
    fn storage_withdraw(&mut self, amount: Option<NearToken>) -> StorageBalance {
        self.malborn_token.storage_withdraw(amount)
    }

    #[payable]
    fn storage_unregister(&mut self, force: Option<bool>) -> bool {
        #[allow(unused_variables)]
        if let Some((account_id, balance)) = self.malborn_token.internal_storage_unregister(force) {
            self.on_account_closed(account_id, balance);
            true
        } else {
            false
        }
    }

    fn storage_balance_bounds(&self) -> StorageBalanceBounds {
        self.malborn_token.storage_balance_bounds()
    }

    fn storage_balance_of(&self, account_id: AccountId) -> Option<StorageBalance> {
        self.malborn_token.storage_balance_of(account_id)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use near_contract_standards::fungible_token::Balance;
    use near_sdk::test_utils::{accounts, VMContextBuilder};
    use near_sdk::testing_env;

    const TOTAL_SUPPLY: Balance = 1_000_000_000;

    fn get_context(
        predecessor_account_id: AccountId,
        signer_account_id: AccountId,
    ) -> VMContextBuilder {
        let mut builder = VMContextBuilder::new();
        builder
            .current_account_id(accounts(0))
            .signer_account_id(signer_account_id)
            .predecessor_account_id(predecessor_account_id);
        builder
    }

    #[test]
    fn test_new() {
        let mut context = get_context(accounts(1), accounts(2));
        testing_env!(context.build());
        let contract = MalbornClubContract::new(accounts(1).into(), TOTAL_SUPPLY.into());
        testing_env!(context.is_view(true).build());

        assert_eq!(contract.ft_total_supply().0, TOTAL_SUPPLY);
        assert_eq!(
            contract.ft_balance_of(accounts(1)),
            U128::from(TOTAL_SUPPLY)
        );
    }

    #[test]
    fn test_mint() {
        let context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        let mint_amount = TOTAL_SUPPLY / 2;

        contract.mint_tokens(&accounts(2), U128::from(mint_amount));
        assert_eq!(
            contract.ft_balance_of(accounts(2)).0,
            TOTAL_SUPPLY + mint_amount
        );
        assert_eq!(contract.ft_total_supply().0, TOTAL_SUPPLY + mint_amount);
    }

    #[test]
    fn test_transfer() {
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());
        testing_env!(context
            .storage_usage(env::storage_usage())
            .attached_deposit(contract.storage_balance_bounds().min.into())
            .predecessor_account_id(accounts(1))
            .build());
        //Paying for account registration => storage deposit
        contract.storage_deposit(None, None);

        testing_env!(context
            .storage_usage(env::storage_usage())
            .attached_deposit(NearToken::from_yoctonear(1))
            .predecessor_account_id(accounts(2))
            .build());
        let transfer_amount = TOTAL_SUPPLY / 3;
        contract.ft_transfer(accounts(1), transfer_amount.into(), None);

        testing_env!(context
            .storage_usage(env::storage_usage())
            .account_balance(env::account_balance())
            .is_view(true)
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        assert_eq!(
            contract.ft_balance_of(accounts(2)).0,
            (TOTAL_SUPPLY - transfer_amount)
        );
        assert_eq!(contract.ft_balance_of(accounts(1)).0, transfer_amount);
    }

    #[test]
    #[should_panic]
    fn test_pause() {
        let context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        let symbol = contract.get_symbol();
        assert_eq!(symbol, "MAL".to_string());
        contract.pause();
        contract.get_symbol();
    }

    #[test]
    fn test_blocklist() {
        let context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());
        assert_eq!(
            contract.get_blocklist_status(&accounts(1)),
            BlocklistStatus::Allowed
        );

        contract.add_to_blocklist(&accounts(1));
        assert_eq!(
            contract.get_blocklist_status(&accounts(1)),
            BlocklistStatus::Banned
        );

        contract.remove_from_blocklist(&accounts(1));
        assert_eq!(
            contract.get_blocklist_status(&accounts(1)),
            BlocklistStatus::Allowed
        );
    }

    #[test]
    #[should_panic]
    fn test_blocklist2() {
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());
        testing_env!(context
            .storage_usage(env::storage_usage())
            .attached_deposit(contract.storage_balance_bounds().min.into())
            .predecessor_account_id(accounts(1))
            .build());
        //Paying for account registration -- storage deposit
        contract.storage_deposit(None, None);

        testing_env!(context
            .storage_usage(env::storage_usage())
            .attached_deposit(NearToken::from_yoctonear(1))
            .predecessor_account_id(accounts(2))
            .build());
        let transfer_amount = TOTAL_SUPPLY / 3;
        contract.ft_transfer(accounts(1), transfer_amount.into(), None);

        assert_eq!(
            contract.get_blocklist_status(&accounts(1)),
            BlocklistStatus::Allowed
        );

        contract.add_to_blocklist(&accounts(1));
        assert_eq!(
            contract.get_blocklist_status(&accounts(1)),
            BlocklistStatus::Banned
        );

        testing_env!(context
            .predecessor_account_id(accounts(1))
            .signer_account_id(accounts(1))
            .build());

        contract.ft_transfer(accounts(2), U128::from(transfer_amount / 2), None);
    }

    // ========== VULNERABILITY TEST CASES ==========

    #[test]
    fn test_resume_bug_contract_stays_paused() {
        // Bug: resume() sets status to Paused instead of Working
        let context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Pause the contract
        contract.pause();
        assert_eq!(contract.contract_status(), ContractStatus::Paused);

        // Try to resume - but bug causes it to stay paused
        contract.resume();
        
        // Contract should be working, but bug keeps it paused
        assert_eq!(contract.contract_status(), ContractStatus::Paused);
    }

    #[test]
    #[should_panic(expected = "Contract is paused")]
    fn test_resume_bug_cannot_use_contract() {
        // Demonstrates that after resume(), contract is still unusable
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Pause and "resume" (which actually keeps it paused)
        contract.pause();
        contract.resume();
        
        // Contract is still paused, so this should fail
        testing_env!(context.is_view(true).build());
        contract.get_symbol();
    }

    #[test]
    fn test_mint_tokens_bug_unregistered_user() {
        // Bug: mint_tokens() increases total_supply but doesn't add tokens to unregistered users
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        let mint_amount = 100_000_000;
        let unregistered_user = accounts(3);

        // Get initial total supply
        let initial_supply = contract.ft_total_supply().0;

        // Try to mint to unregistered user
        let new_supply = contract.mint_tokens(&unregistered_user, U128::from(mint_amount));

        // Total supply increased
        assert_eq!(new_supply, initial_supply + mint_amount);
        assert_eq!(contract.ft_total_supply().0, initial_supply + mint_amount);

        // But user has no balance (not registered) - tokens are lost
        testing_env!(context.is_view(true).build());
        let balance = contract.ft_balance_of(unregistered_user);
        assert_eq!(balance.0, 0); // User has no balance - tokens are effectively lost!
    }

    #[test]
    fn test_mint_tokens_bug_token_loss() {
        // Demonstrates token loss from mint_tokens bug
        // The bug: total_supply increases but user balance is 0 (tokens are lost)
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        let mint_amount = 100_000_000;
        let unregistered_user = accounts(3);

        // Mint to unregistered user - increases supply but doesn't register user
        contract.mint_tokens(&unregistered_user, U128::from(mint_amount));

        // Check balance - user has 0 balance even though we "minted" to them
        testing_env!(context.is_view(true).build());
        let balance = contract.ft_balance_of(unregistered_user);
        assert_eq!(balance.0, 0); // User has no balance - tokens are lost!
        
        // But total supply increased
        assert_eq!(contract.ft_total_supply().0, TOTAL_SUPPLY + mint_amount);
    }

    #[test]
    #[should_panic]
    fn test_metadata_consumption_bug() {
        // Bug: get_symbol/get_name/get_decimals consume metadata with take()
        // After consuming, ft_metadata() will fail because metadata is None
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // First call works (consumes metadata)
        let symbol = contract.get_symbol();
        assert_eq!(symbol, "MAL".to_string());

        // Metadata is now consumed, so ft_metadata() will panic
        testing_env!(context.is_view(true).build());
        contract.ft_metadata(); // This will panic: "called `Option::unwrap()` on a `None` value"
    }

    #[test]
    #[should_panic]
    fn test_metadata_consumption_bug_multiple_functions() {
        // Demonstrates that any metadata function call consumes it
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Call get_name - consumes metadata
        let name = contract.get_name();
        assert_eq!(name, "Malborn Token".to_string());

        // Now ft_metadata() fails because metadata was consumed
        testing_env!(context.is_view(true).build());
        contract.ft_metadata(); // This will panic because metadata is None
    }

    #[test]
    #[should_panic]
    fn test_metadata_consumption_bug_ft_metadata() {
        // Demonstrates that ft_metadata() also fails after metadata is consumed
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Consume metadata with get_decimals
        let decimals = contract.get_decimals();
        assert_eq!(decimals, 10);

        // Now ft_metadata() fails because metadata was consumed (None)
        testing_env!(context.is_view(true).build());
        contract.ft_metadata(); // This will panic: "called `Option::unwrap()` on a `None` value"
    }

    #[test]
    #[should_panic(expected = "attempt to divide by zero")]
    fn test_registration_fee_denominator_zero_division() {
        // Bug: Owner can set registration_fee_denominator to 0, causing division by zero
        let context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Set associated contract
        contract.set_associated_contract(accounts(3));

        // Owner sets denominator to 0
        contract.set_registration_fee_denominator(U128::from(0));

        // Register for event - this will panic due to division by zero
        contract.register_for_event(U128::from(1));
    }

    #[test]
    fn test_register_for_event_burns_tokens_before_external_call() {
        // Bug: Tokens are burned BEFORE external call. If external call fails, tokens are lost
        // This is a critical issue - users lose tokens without getting registered
        // The issue: burn_tokens_internal() is called BEFORE the external promise
        // If the promise fails (event doesn't exist, event offline, etc.), tokens are still burned
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Register user and give them tokens
        testing_env!(context
            .storage_usage(env::storage_usage())
            .attached_deposit(contract.storage_balance_bounds().min.into())
            .predecessor_account_id(accounts(2))
            .build());
        contract.storage_deposit(None, None);
        
        // Give user some tokens
        testing_env!(context
            .predecessor_account_id(accounts(2))
            .signer_account_id(accounts(2))
            .build());
        contract.mint_tokens(&accounts(2), U128::from(1_000_000_000));
        
        // Check balances before (ft_balance_of calls not_paused which needs signer_account_id)
        let balance_before = contract.ft_balance_of(accounts(2)).0;
        let supply_before = contract.ft_total_supply().0;

        // Set associated contract to an address that exists but isn't set up properly
        // This simulates a scenario where the external call will fail
        // (e.g., event doesn't exist, contract not in privileged_clubs, etc.)
        contract.set_associated_contract(accounts(3));

        // Calculate burn amount
        let burn_amount = supply_before / 10000; // Default denominator is 10000

        // Try to register for a non-existent event
        // Tokens will be burned BEFORE the external call
        // External call will fail (event doesn't exist), but tokens are already burned
        // Note: register_for_event() will fail when calling the external contract,
        // but tokens are already burned at this point
        contract.register_for_event(U128::from(999)); // Non-existent event

        // Verify tokens were burned (check balances after)
        let balance_after = contract.ft_balance_of(accounts(2)).0;
        let supply_after = contract.ft_total_supply().0;
        
        // Tokens were burned even though registration will fail
        // This demonstrates the bug: tokens burned without successful registration
        assert_eq!(balance_after, balance_before - burn_amount);
        assert_eq!(supply_after, supply_before - burn_amount);
    }

    #[test]
    #[should_panic(expected = "Contract is paused")]
    fn test_ft_total_supply_breaks_when_paused() {
        // Bug: ft_total_supply() calls not_paused(), breaking FT standard
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Pause the contract
        contract.pause();

        // FT standard view function should work, but it fails when paused
        testing_env!(context.is_view(true).build());
        contract.ft_total_supply(); // This will panic: "Contract is paused"
    }

    #[test]
    #[should_panic(expected = "Contract is paused")]
    fn test_ft_balance_of_breaks_when_paused() {
        // Bug: ft_balance_of() calls not_paused(), breaking FT standard
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Pause the contract
        contract.pause();

        // FT standard view function should work, but it fails when paused
        testing_env!(context.is_view(true).build());
        contract.ft_balance_of(accounts(2)); // This will panic: "Contract is paused"
    }

    #[test]
    #[should_panic(expected = "Contract is paused")]
    fn test_get_blocklist_status_breaks_when_paused() {
        // Bug: get_blocklist_status() calls not_paused(), causing DoS
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());

        // Pause the contract
        contract.pause();

        // View function should work, but it fails when paused
        testing_env!(context.is_view(true).build());
        contract.get_blocklist_status(&accounts(1)); // This will panic: "Contract is paused"
    }

    #[test]
    fn test_set_associated_contract_no_validation() {
        // Bug: set_associated_contract() doesn't validate account ID
        // Can set to self, invalid account, or create circular dependencies
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());
        
        // BUG: Can set associated contract to self - creates circular dependency
        // Should validate that account_id != current_account_id, but doesn't
        let current_account = env::current_account_id();
        contract.set_associated_contract(current_account.clone());
        
        // Verify it was set (even though it's invalid)
        testing_env!(context.is_view(true).build());
        let associated = contract.associated_contract_account_id.get();
        assert_eq!(associated, Some(current_account));
        
        // This creates a circular dependency where the contract references itself
        // If register_for_event() is called, it will try to call itself, causing issues
    }

    #[test]
    fn test_set_associated_contract_invalid_account() {
        // Bug: set_associated_contract() doesn't validate that account exists or is valid
        // Can set to any account ID without validation
        let mut context = get_context(accounts(2), accounts(2));
        testing_env!(context.build());
        let mut contract = MalbornClubContract::new(accounts(2).into(), TOTAL_SUPPLY.into());
        
        // Set to a non-existent or invalid account
        // Should validate account exists, but doesn't
        // Use a string-based AccountId to represent a non-existent account
        let invalid_account: AccountId = "nonexistent-contract.near".parse().unwrap();
        let invalid_account_clone = invalid_account.clone();
        contract.set_associated_contract(invalid_account);
        
        // Verify it was set (even though account may not exist)
        testing_env!(context.is_view(true).build());
        let associated = contract.associated_contract_account_id.get();
        assert_eq!(associated, Some(invalid_account_clone));
        
        // If register_for_event() is called, it will try to call a non-existent contract
        // This will cause promise failures and token loss (tokens burned before external call)
        // This demonstrates the lack of account validation
    }
}
