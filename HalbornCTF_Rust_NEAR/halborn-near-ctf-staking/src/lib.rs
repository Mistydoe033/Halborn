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
        // This is a logic error but may not be exploitable
        let mut context = get_context(accounts(1), accounts(1));
        testing_env!(context.build());

        let mut contract = StakingContract::new();

        // Stake 10 NEAR
        testing_env!(context
            .attached_deposit(NearToken::from_near(10))
            .build());
        contract.stake();

        // Try to unstake 100 NEAR (more than we have)
        // saturating_sub(10, 100) = 0
        // new_balance will be 0, so it will refund 'balance' (10 NEAR)
        // This is actually correct behavior, but the logic is confusing
        testing_env!(context
            .attached_deposit(NearToken::from_yoctonear(0))
            .build());
        
        // The function should check amount <= balance, but it doesn't
        // This will set balance to 0 and refund 10 NEAR
        contract.unstake(U128::from(NearToken::from_near(100).as_yoctonear()));
        
        // Balance is now 0
        assert_eq!(contract.get_user_staked(), 0);
        // But total_staked was reduced by 100, not 10!
        // This is the actual bug - total_staked becomes incorrect
    }
}
