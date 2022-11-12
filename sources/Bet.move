module publisher::adf_bet {
    use std::signer;
    use std::vector;
    use std::coin;
    // use aptos_framework::account;
    // use aptos_framework::event;
	use aptos_framework::table::{Self, Table};

    const MODULE_ADMIN: address = @publisher;
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_MODULE_NOT_INITIALIZE: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const INVALID_INPUT: u64 = 3;
    const ERROR_EXCEED_MAKER_POT: u64 = 4;
    const ERROR_ALREADY_CLAIM: u64 = 5;
    const ERROR_NOT_WINNER: u64 = 6;
    const ERROR_INVALID_AMOUNT:u64 = 7;
    const PROVIDER_FEE: u64 = 100;
	const MAKER_WIN: u8 = 1;
	const TAKER_WIN: u8 = 2;
	const BOTH_WIN: u8= 100;
	const DIVIDER: u64 = 10000;

    struct Order<phantom T> has store{
        makerClaimed: bool,
        winner: u8,
        betType: u8,
        status: u8,
        odds: u64,
        startTime: u64,
        matchId: u64,
        makerTotalPot: u64,
        makerPot: u64,
        takerPot: u64,
        makerSide: address,
        tokenCode: u8,

        details: Table<address, OrderDetail>,
        takers: vector<address>,
        updateResultTime: u64,
        treasury: coin::Coin<T>,
  }
    struct OrderDetail has store{
        wallet: address,
        amount: u64,
        claimed: bool
    }
	struct ChipToken has store{
        tokenAddress: address,
        isSupport: bool,
        _MINIMUM_BET: u64,
        isFreeFee: bool,
        fee: u64
    }
	struct Gambling<phantom T> has key{
		insuranceAddress: address,
		orders: Table<u64, vector<Order<T>>>,
		// orderGroups: Table<u64, Table<u64, u64>>
	}
    public entry fun createGambling<T>(owner: &signer, insuranceAddress: address) {
		let orders = table::new<u64, vector<Order<T>>>();
		move_to(owner, Gambling<T> {insuranceAddress, orders});
	}    
    

	public fun isTokenSupported<T>(): bool {
       if(exists<Gambling<T>>(MODULE_ADMIN)) {
            return true
       };
       false
	}

    public fun placeMakerSide<T>(maker: &signer, makerParams: vector<u64>): u64 acquires Gambling {
		assert!(vector::length<u64>(&makerParams) == 7, INVALID_INPUT);
        assert!(exists<Gambling<T>>(MODULE_ADMIN), ERROR_MODULE_NOT_INITIALIZE);
		let gambling = borrow_global_mut<Gambling<T>>(MODULE_ADMIN);

		let matchId = (*vector::borrow(&makerParams, 0) as u64);
		let odds = (*vector::borrow(&makerParams, 1) as u64);
		let startTime = (*vector::borrow(&makerParams, 2) as u64);
		let endTime =(*vector::borrow(&makerParams, 3) as u64);
		let makerTotalPot = (*vector::borrow(&makerParams, 4) as u64);
		let betType = (*vector::borrow(&makerParams, 5) as u8);
		let tokenCode = (*vector::borrow(&makerParams, 6)  as u8);
		assert!(startTime < endTime, 3);
		assert!(odds > 100, 4);

        if(!table::contains(&gambling.orders, matchId)) {
            table::add(&mut gambling.orders, matchId, vector<Order<T>>[]);
        };
        let matchInfo = table::borrow_mut(&mut gambling.orders, matchId);

		let orderId = vector::length<Order<T>>(matchInfo);


        let depositCoin = coin::withdraw<T>(maker, makerTotalPot);
		let makerDetail = Order<T>{matchId: matchId, odds: odds, startTime: startTime, makerTotalPot: makerTotalPot, betType: betType, tokenCode: tokenCode, status: 99, makerSide: signer::address_of(maker), makerClaimed: false, details: table::new<address, OrderDetail>(), makerPot:0,takerPot:0, updateResultTime:0, winner:0, takers: vector::empty<address>(), treasury: depositCoin};
        vector::push_back<Order<T>>(matchInfo, makerDetail);

		return orderId
	}
    public fun placeTakerSide<T>(maker: &signer, matchId: u64, orderId: u64, amount: u64) acquires Gambling {
		let gambling = borrow_global_mut<Gambling<T>>(MODULE_ADMIN);
        let orders = table::borrow_mut(&mut gambling.orders, matchId);
        let order = vector::borrow_mut<Order<T>>(orders, orderId);
        let makerFilled = (order.odds - 100) * amount / 100;
        order.makerPot = order.makerPot + makerFilled;

        assert!(amount > 0, ERROR_INVALID_AMOUNT);
        assert!(order.makerPot<=order.makerTotalPot, ERROR_EXCEED_MAKER_POT);

        let depositCoin = coin::withdraw<T>(maker, amount);
        coin::merge(&mut order.treasury, depositCoin);

        if(!table::contains(&mut order.details, signer::address_of(maker))) {
            vector::push_back(&mut order.takers, signer::address_of(maker));
		    table::add(&mut order.details, signer::address_of(maker), OrderDetail{wallet: signer::address_of(maker), amount: amount, claimed: false});
        } else {
            let orderDetail = table::borrow_mut(&mut order.details, signer::address_of(maker));
            orderDetail.amount = orderDetail.amount + amount;
        };
        order.takerPot = order.takerPot + amount;
	}
    public fun setMatchResult<T>(admin: &signer, matchId: u64, orderId: u64, betType: u8, winner: u8) acquires Gambling {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, ERROR_ONLY_ADMIN);
		let gambling = borrow_global_mut<Gambling<T>>(MODULE_ADMIN);
        let orders = table::borrow_mut(&mut gambling.orders, matchId);
		let orderCount = vector::length<Order<T>>(orders);
        let count = 0;
        while(count < orderCount) {
            let order = vector::borrow_mut<Order<T>>(orders, orderId);
            if(order.betType == betType) {
                order.winner = winner;
            };
            count = count + 1;
        }
	}
    public fun claim<T>(signer: &signer, matchId: u64, orderId: u64) acquires Gambling {
        let signerAddress = signer::address_of(signer);
		let gambling = borrow_global_mut<Gambling<T>>(MODULE_ADMIN);
        let orders = table::borrow_mut(&mut gambling.orders, matchId);
        let order = vector::borrow_mut<Order<T>>(orders, orderId);
        if(order.winner == MAKER_WIN) {
            assert!(!order.makerClaimed, ERROR_ALREADY_CLAIM);
            assert!(order.makerSide == signerAddress, ERROR_NOT_WINNER);

            let winAmount = coin::value<T>(&order.treasury);
            let depositCoin = coin::extract<T>(&mut order.treasury, winAmount);
            coin::deposit(signerAddress, depositCoin);
        } else if (order.winner == TAKER_WIN) {
            assert!(table::contains(&order.details, signerAddress), ERROR_NOT_WINNER);
            let orderDetail = table::borrow_mut(&mut order.details, signerAddress);
            assert!(!orderDetail.claimed, ERROR_ALREADY_CLAIM);

            let winAmount = orderDetail.amount * order.odds / 100;
            let depositCoin = coin::extract<T>(&mut order.treasury, winAmount);
            coin::deposit(signerAddress, depositCoin);
        }
	}

    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use aptos_framework::managed_coin;
    #[test_only]
    use publisher::adf_util;
    #[test_only]
    struct TestCoin {}
    #[test (origin_account = @0xcaffee, acount2 = @0xffffa, nft_receiver = @0x123, nft_receiver2 = @0x234, aptos_framework = @aptos_framework)]
    public fun test_test(origin_account: signer, acount2: signer)  acquires Gambling{
        create_account_for_test(signer::address_of(&origin_account));
        create_account_for_test(signer::address_of(&acount2));

        managed_coin::initialize<TestCoin>(
                &origin_account,
                b"USDT",
                b"USDT",
                8, false
            );

        adf_util::check_coin_store<TestCoin>(&origin_account);
        adf_util::check_coin_store<TestCoin>(&acount2);
        managed_coin::mint<TestCoin>(&origin_account, signer::address_of(&origin_account), 1000000000000);
        managed_coin::mint<TestCoin>(&origin_account, signer::address_of(&acount2), 1000000000000);
        {

                createGambling<TestCoin>(&origin_account, signer::address_of(&origin_account));
                let orderId = placeMakerSide<TestCoin>(&origin_account, vector<u64>[1, 120, 100, 200, 1000000, 1, 1]);
                assert!(coin::balance<TestCoin>(signer::address_of(&origin_account))== 999999000000, 0);

                placeTakerSide<TestCoin>(&acount2, 1, orderId, 1000000);
                assert!(coin::balance<TestCoin>(signer::address_of(&acount2))== 999999000000, 0);
                setMatchResult<TestCoin>(&origin_account, 1, orderId, 1, MAKER_WIN);
                claim<TestCoin>(&origin_account, 1, orderId);
                let balance = coin::balance<TestCoin>(signer::address_of(&origin_account));
                assert!(coin::balance<TestCoin>(signer::address_of(&origin_account))== 1000001000000, balance);
        };
        {

                let orderId = placeMakerSide<TestCoin>(&origin_account, vector<u64>[1, 120, 100, 200, 1000000, 1, 1]);
                assert!(coin::balance<TestCoin>(signer::address_of(&origin_account))== 1000000000000, 0);

                placeTakerSide<TestCoin>(&acount2, 1, orderId, 1000000);
                assert!(coin::balance<TestCoin>(signer::address_of(&acount2))== 999998000000, 0);
                setMatchResult<TestCoin>(&origin_account, 1, orderId, 1, TAKER_WIN);
                claim<TestCoin>(&acount2, 1, orderId);
                let balance = coin::balance<TestCoin>(signer::address_of(&acount2));
                assert!(coin::balance<TestCoin>(signer::address_of(&acount2))== 999999200000, balance);
        }
    }
}