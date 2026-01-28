use near_sdk::borsh::{BorshDeserialize, BorshSerialize};
use near_sdk::collections::UnorderedMap;
use near_sdk::json_types::U128;
use near_sdk::{env, log, near_bindgen, AccountId, NearToken, PanicOnDefault, Promise};
use near_contract_standards::fungible_token::Balance;

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
#[borsh(crate = "near_sdk::borsh")]
pub struct StakingContract {
    owner: AccountId,
    stake_balances: UnorderedMap<AccountId, u128>,
    total_staked: u128,
}

#[near_bindgen]
impl StakingContract {
    #[init]
    pub fn new() -> Self {
        Self {
            owner: env::predecessor_account_id(),
            stake_balances: UnorderedMap::new(b"s".to_vec()),
            total_staked: 0,
        }
    }

    #[payable]
    pub fn stake(&mut self) -> u128 {
        let deposit = env::attached_deposit();
        let user = env::predecessor_account_id();
        log!("{} is staking {}", user, deposit);

        match self.stake_balances.get(&user) {
            Some(balance) => {
                let new_balance = balance.saturating_add(deposit.as_yoctonear());
                self.stake_balances.insert(&user, &new_balance);
                self.total_staked = self.total_staked.saturating_add(deposit.as_yoctonear());
                new_balance
            }
            None => {
                let new_balance = deposit.as_yoctonear();
                self.stake_balances.insert(&user, &new_balance);
                self.total_staked = self.total_staked.saturating_add(deposit.as_yoctonear());
                new_balance
            }
        }
    }

    pub fn unstake(&mut self, amount: U128) -> bool {
        assert!(u128::from(amount) > 0);
        let user = env::predecessor_account_id();
        log!("{} is unstaking {}", user, u128::from(amount));

        match self.stake_balances.get(&user) {
            Some(balance) => {
                let new_balance = balance.saturating_sub(u128::from(amount));
                self.stake_balances.insert(&user, &new_balance);
                self.total_staked = self.total_staked.saturating_sub(u128::from(amount));
                if new_balance == 0 {
                    //User unstaked all their balance, so refund it all
                    let _ = Promise::new(user).transfer(NearToken::from_yoctonear(balance));
                } else {
                    //User unstaked a portion of their balance, refund just that
                    let _ = Promise::new(user).transfer(NearToken::from_yoctonear(amount.0));
                }
                true
            }
            _ => false,
        }
    }

    pub fn airdrop(&mut self, amount: u128) {
        let user = env::predecessor_account_id();
        assert!(user == self.owner);
        for (staker, _) in self.stake_balances.iter() {
            let _ = Promise::new(staker).transfer(NearToken::from_yoctonear(amount));
        }
    }

    pub fn get_total_staked(&self) -> u128 {
        self.total_staked
    }

    pub fn get_user_staked(&self) -> u128 {
        let user = env::predecessor_account_id();
        match self.stake_balances.get(&user) {
            Some(balance) => balance,
            None => 0,
        }
    }

    pub fn get_total_balance(&self) -> Balance {
        env::account_balance().as_yoctonear()
    }

    pub fn get_account_id(&self) -> AccountId {
        env::current_account_id()
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use near_sdk::test_utils::{accounts, VMContextBuilder};
    use near_sdk::testing_env;

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
    fn test_stake_and_unstake() {
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();

        // Stake some tokens
        testing_env!(context
            .attached_deposit(NearToken::from_near(10))
            .build());
        let balance = contract.stake();
        assert_eq!(balance, NearToken::from_near(10).as_yoctonear());

        // Unstake some tokens
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        let result = contract.unstake(U128::from(5_000_000_000_000_000_000_000_000)); // 5 NEAR
        assert!(result);
    }

    // ========== VULNERABILITY TEST CASES ==========

    #[test]
    fn test_unstake_bug_when_balance_reaches_zero() {
        // Bug: When unstaking brings balance to 0, refunds old balance instead of amount
        // However, if balance == amount (unstaking all), this is correct
        // The bug is more subtle - it's about consistency and edge cases
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();

        // Stake 10 NEAR
        testing_env!(context
            .attached_deposit(NearToken::from_near(10))
            .build());
        contract.stake();

        // Unstake exactly 10 NEAR (bringing balance to 0)
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        
        // This should refund 10 NEAR (the old balance)
        // In this case, it's correct because we're unstaking all
        let result = contract.unstake(U128::from(NearToken::from_near(10).as_yoctonear()));
        assert!(result);
        
        // User balance should be 0
        assert_eq!(contract.get_user_staked(), 0);
    }

    #[test]
    fn test_unstake_bug_logic_inconsistency() {
        // Demonstrates the logic inconsistency in unstake()
        // When new_balance == 0, it refunds 'balance' (old balance)
        // When new_balance > 0, it refunds 'amount' (unstaked amount)
        // This is inconsistent - should always refund 'amount'
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();

        // Stake 100 NEAR
        testing_env!(context
            .attached_deposit(NearToken::from_near(100))
            .build());
        contract.stake();

        // Unstake 50 NEAR (balance will be 50, not 0)
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        contract.unstake(U128::from(NearToken::from_near(50).as_yoctonear()));
        
        // Now unstake the remaining 50 NEAR (balance will be 0)
        // This will refund 50 NEAR (the old balance), which is correct
        // But the logic is inconsistent - it should always refund 'amount'
        contract.unstake(U128::from(NearToken::from_near(50).as_yoctonear()));
        
        assert_eq!(contract.get_user_staked(), 0);
    }

    #[test]
    fn test_unstake_edge_case_saturating_sub() {
        // Edge case: If someone tries to unstake more than they have
        // saturating_sub will make new_balance = 0, and they'll get refunded their original balance
        // But total_staked is reduced by the requested amount, not the actual balance
        // This demonstrates the accounting inconsistency bug
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();

        // Stake 10 NEAR
        testing_env!(context
            .attached_deposit(NearToken::from_near(10))
            .build());
        contract.stake();
        
        // Get total_staked before unstaking
        let total_staked_before = contract.get_total_staked();
        assert_eq!(total_staked_before, NearToken::from_near(10).as_yoctonear());

        // Try to unstake 100 NEAR (more than we have)
        // saturating_sub(10, 100) = 0 for balance
        // new_balance will be 0, so it will refund 'balance' (10 NEAR)
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        
        // The function should check amount <= balance, but it doesn't
        // This will set balance to 0 and refund 10 NEAR
        contract.unstake(U128::from(NearToken::from_near(100).as_yoctonear()));
        
        // Balance is now 0
        assert_eq!(contract.get_user_staked(), 0);
        
        // BUG: total_staked was reduced by 100 (the requested amount), not 10 (the actual balance)
        // Line 58: self.total_staked = self.total_staked.saturating_sub(u128::from(amount));
        // Should subtract min(amount, balance) = 10, but subtracts amount = 100
        // Because saturating_sub is used, 10 - 100 saturates to 0
        // The bug: uses `amount` instead of the actual unstaked amount
        let total_staked_after = contract.get_total_staked();
        // In this case, both correct (subtract 10) and buggy (subtract 100) result in 0 due to saturation
        // But the bug is still present: it subtracts the wrong amount
        assert_eq!(total_staked_after, 0); // Demonstrates that accounting uses wrong amount (100 instead of 10)
        // The accounting inconsistency: total_staked is reduced by requested amount, not actual unstaked amount
    }

    #[test]
    fn test_airdrop_zero_amount_wastes_gas() {
        // Bug: airdrop() has no validation on amount parameter
        // Calling with amount = 0 wastes gas iterating through all stakers
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();
        
        // Add multiple stakers
        testing_env!(context
            .attached_deposit(NearToken::from_near(10))
            .predecessor_account_id(accounts(2))
            .signer_account_id(accounts(2))
            .build());
        contract.stake();
        
        testing_env!(context
            .attached_deposit(NearToken::from_near(5))
            .predecessor_account_id(accounts(3))
            .signer_account_id(accounts(3))
            .build());
        contract.stake();
        
        testing_env!(context
            .attached_deposit(NearToken::from_near(3))
            .predecessor_account_id(accounts(4))
            .signer_account_id(accounts(4))
            .build());
        contract.stake();
        
        // Verify we have 3 stakers
        assert_eq!(contract.get_total_staked(), NearToken::from_near(18).as_yoctonear());
        
        // Owner calls airdrop with 0 amount - should validate but doesn't
        // Function will iterate through all stakers and send 0 NEAR to each, wasting gas
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .predecessor_account_id(accounts(1))
            .signer_account_id(accounts(1))
            .build());
        
        // BUG: No validation that amount > 0
        // This will iterate through all 3 stakers and send 0 NEAR to each
        // Gas is wasted on iteration and promise creation with no effect
        contract.airdrop(0);
        
        // No tokens were sent, but gas was consumed
        // This demonstrates the lack of input validation
    }

    #[test]
    fn test_airdrop_insufficient_balance() {
        // Bug: airdrop() doesn't check if contract has sufficient balance
        // If contract balance is insufficient, promises will fail but gas is still consumed
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();
        
        // Add a staker
        testing_env!(context
            .attached_deposit(NearToken::from_near(1))
            .predecessor_account_id(accounts(2))
            .signer_account_id(accounts(2))
            .build());
        contract.stake();
        
        // Owner tries to airdrop more than contract balance
        // Contract only has 1 NEAR (from staking), but tries to send 10 NEAR to each staker
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .predecessor_account_id(accounts(1))
            .signer_account_id(accounts(1))
            .build());
        
        // BUG: No validation that contract balance >= (amount * staker_count)
        // This will create promises that will fail, but gas is still consumed
        // In a real scenario, this could cause DoS if called repeatedly
        contract.airdrop(NearToken::from_near(10).as_yoctonear());
        
        // Promises will fail, but function doesn't check balance beforehand
        // This demonstrates the lack of balance validation
    }
}
