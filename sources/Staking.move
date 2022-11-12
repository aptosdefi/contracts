
module publisher::adf_stake {
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use publisher::adf_util;
    use publisher::adf_ref;
    use aptos_std::table::{Self, Table};
    use std::vector;
    #[test_only]
    use aptos_framework::account::create_account_for_test;

    const MODULE_ADMIN: address = @publisher;

    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_COIN_NOT_INITIALIZED: u64 = 2;
    const ERROR_NOT_CREATOR: u64 = 3;
    const EACCOUNT_NOT_FOUND: u64 = 4;
    const EACCOUNT_INVALID_STAKE_ID: u64 = 5;
    const ERROR_STAKETIME_TOOSMALL: u64 = 6;
    const Divider:u128 = 10000;
    const SECOND_PER_YEAR: u128= 31540000;

    

    struct Treasury<phantom X> has key {
        staking: coin::Coin<X>,
        totalStaking: u128,
        stakeInfo : Table<address, vector<StakeInfo>>,
        apy: u128,
        refBonus: u128,
    }
    struct StakeInfo has store, copy, drop{
        amount: u128,
        startTime:u64,
        duration: u64,
        apy: u128,
        refBonus: u128,
    }

    public entry fun createNewStake<CoinType>(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);
        assert!(!exists<Treasury<CoinType>>(admin_addr), ERROR_ALREADY_INITIALIZED);
        adf_util::check_coin_store<CoinType>(admin);
        move_to<Treasury<CoinType>>(admin, Treasury<CoinType>{staking: coin::zero<CoinType>(), totalStaking: 0, stakeInfo: table::new(), apy: 12000, refBonus: 500});
    }
    public entry fun updateAPY<CoinType>(admin: &signer, newApy: u128)  acquires Treasury{
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);
        assert!(exists<Treasury<CoinType>>(admin_addr), ERROR_COIN_NOT_INITIALIZED);
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);
        treasury.apy = newApy;
    }
    public entry fun updateRefRate<CoinType>(admin: &signer, newRefBonus: u128)  acquires Treasury{
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);
        assert!(exists<Treasury<CoinType>>(admin_addr), ERROR_COIN_NOT_INITIALIZED);
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);
        treasury.refBonus = newRefBonus;
    }
    public entry fun addReward<CoinType>(admin: &signer, amount: u64)  acquires Treasury{
        assert!(exists<Treasury<CoinType>>(signer::address_of(admin)), ERROR_COIN_NOT_INITIALIZED);
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);
        let reward = coin::withdraw<CoinType>(admin, amount);
        coin::merge(&mut treasury.staking, reward);
    }
    
    public entry fun stake<CoinType>(sender: &signer, stakeAmount: u128) acquires Treasury{
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);

        let stakeCoin = coin::withdraw<CoinType>(sender, (stakeAmount as u64));
        coin::merge(&mut treasury.staking, stakeCoin);

        let senderAddress = signer::address_of(sender);
        if(!table::contains(&mut treasury.stakeInfo, senderAddress)) {
            table::add(&mut treasury.stakeInfo, senderAddress, vector<StakeInfo>[]);
        };

        let refs = table::remove(&mut treasury.stakeInfo, senderAddress);
        let (hasRef, _) = adf_ref::getReferer<CoinType>(sender);
        if(hasRef) {
            vector::push_back(&mut refs, StakeInfo{amount: stakeAmount, startTime:  timestamp::now_seconds(), duration: 10 * 24 * 60 *60, apy: treasury.apy, refBonus: treasury.refBonus});
        } else {
            vector::push_back(&mut refs, StakeInfo{amount: stakeAmount, startTime:  timestamp::now_seconds(), duration: 10 * 24 * 60 *60, apy: treasury.apy, refBonus: 0});
        };
        table::add(&mut treasury.stakeInfo, senderAddress, refs);
    }
    public entry fun unstake<CoinType>(sender: &signer, stakeId: u64) acquires Treasury{
        let senderAddress = signer::address_of(sender);
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);
        assert!(table::contains(&mut treasury.stakeInfo, senderAddress), EACCOUNT_NOT_FOUND);

        let refs = *table::borrow_mut(&mut treasury.stakeInfo, senderAddress);
        
        assert!(vector::length(&refs) > stakeId, EACCOUNT_INVALID_STAKE_ID);

        let refs = table::remove(&mut treasury.stakeInfo, senderAddress);
        let stakeInfo = vector::swap_remove(&mut refs, stakeId);
        table::add(&mut treasury.stakeInfo, senderAddress, refs);

        let stakedTime = timestamp::now_seconds() - stakeInfo.startTime;
        assert!(stakedTime > 0, ERROR_STAKETIME_TOOSMALL);
        let stakeReward = stakeInfo.amount * stakeInfo.apy / Divider * (stakedTime as u128)/ SECOND_PER_YEAR;
        
        let (hasRef, referer) = adf_ref::getReferer<CoinType>(sender);
        if(hasRef && stakeInfo.refBonus > 0) {
            let refBonus = stakeReward * stakeInfo.refBonus / Divider;
            stakeReward = stakeReward + refBonus;
            let referBonus = coin::extract<CoinType>(&mut treasury.staking, (refBonus as u64));
            coin::deposit<CoinType>(referer, referBonus);
        };
        let stakeRewardCoin = coin::extract<CoinType>(&mut treasury.staking, (stakeReward as u64));

        coin::deposit<CoinType>(signer::address_of(sender), stakeRewardCoin);
    }
    public entry fun getStake<CoinType>(sender: &signer): vector<StakeInfo> acquires Treasury{
        let senderAddress = signer::address_of(sender);
        let treasury = borrow_global_mut<Treasury<CoinType>>(MODULE_ADMIN);
        assert!(table::contains(&mut treasury.stakeInfo, senderAddress), EACCOUNT_NOT_FOUND);

        *table::borrow_mut(&mut treasury.stakeInfo, senderAddress)
    }
    #[test_only]
    struct ADF {}
    #[test_only]
    use aptos_framework::managed_coin;
    #[test (origin_account = @0xcaffee, acount2 = @0xcffff, aptos_framework = @aptos_framework)]
    public(friend) fun test_test(aptos_framework: signer, origin_account: signer, acount2 :signer) acquires Treasury {    
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        create_account_for_test(signer::address_of(&origin_account));
        create_account_for_test(signer::address_of(&acount2));
        managed_coin::initialize<ADF>(
                &origin_account,
                b"USDT",
                b"USDT",
                8, false
            );
        adf_util::check_coin_store<ADF>(&origin_account);
        adf_util::check_coin_store<ADF>(&acount2);
        managed_coin::mint<ADF>(&origin_account, signer::address_of(&origin_account), 1000000000000);
        managed_coin::mint<ADF>(&origin_account, signer::address_of(&acount2), 1000000000000);
        assert!(coin::balance<ADF>(signer::address_of(&origin_account))== 1000000000000, 0);
        assert!(coin::balance<ADF>(signer::address_of(&acount2))== 1000000000000, 0);

        createNewStake<ADF>(&origin_account);
        addReward<ADF>(&origin_account, 1000000000000);
        assert!(coin::balance<ADF>(signer::address_of(&origin_account))== 0, 0);
        stake<ADF>(&acount2, 1000000000000);
        assert!(coin::balance<ADF>(signer::address_of(&acount2))== 0, 0);
        
        timestamp::fast_forward_seconds((SECOND_PER_YEAR as u64));
        
        unstake<ADF>(&acount2, 0);
        assert!(coin::balance<ADF>(signer::address_of(&acount2))== 1200000000000, coin::balance<ADF>(signer::address_of(&acount2)));
    }
}