
module publisher::adf_ref {
    use std::signer;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;

    const MODULE_ADMIN: address = @publisher;

    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_REF_PROGRAM_NOT_INIT: u64 = 1;
    const ERROR_USER_HAS_REGISTER_ALREADY: u64 = 2;
    const ERROR_NOT_CREATOR: u64 = 3;
    const ERROR_USER_NOT_FOUND: u64 = 4;
    const ERROR_USER_NOT_WHITELIST: u64 = 5;
    const INVALID_REFERER: u64 = 6;
    const MIN_ADX_OF_REFERER:u64 = 1000000000000;

    struct RefProgram<phantom ADF> has key{
        refMap: Table<address, vector<address>>, 
        userRef: Table<address, address>,
    }

    public entry fun createRefProgram<ADF>(sender: &signer) {
        let admin_addr = signer::address_of(sender);
        assert!(admin_addr == MODULE_ADMIN, ERROR_ONLY_ADMIN);
        move_to(sender, RefProgram<ADF>{refMap: table::new(), userRef: table::new()});
    }
    
    public entry fun regRef<ADF>(sender: &signer, referer: address) acquires RefProgram{

        assert!(exists<RefProgram<ADF>>(MODULE_ADMIN), ERROR_REF_PROGRAM_NOT_INIT);
        let refProgram = borrow_global_mut<RefProgram<ADF>>(MODULE_ADMIN);

        assert!(coin::balance<ADF>(referer)>= MIN_ADX_OF_REFERER, INVALID_REFERER);
        assert!(!table::contains(&mut refProgram.userRef, signer::address_of(sender)), ERROR_USER_HAS_REGISTER_ALREADY);

        table::add(&mut refProgram.userRef, signer::address_of(sender), referer);

        if(!table::contains(&mut refProgram.refMap, referer)) {
            table::add(&mut refProgram.refMap, referer, vector<address>[]);
        };
        let refs = table::borrow_mut(&mut refProgram.refMap, referer);

        // let refs = table::remove(&mut refProgram.refMap, referer);
        vector::push_back<address>(refs, referer);
        // table::add(&mut refProgram.refMap, referer, refs);
    }

    public entry fun getReferer<ADF>(sender: &signer) : (bool, address) acquires RefProgram{
        
        if(!exists<RefProgram<ADF>>(MODULE_ADMIN)) {
            return (false, MODULE_ADMIN)
        };
        let refProgram = borrow_global_mut<RefProgram<ADF>>(MODULE_ADMIN);
        if(!table::contains(&mut refProgram.userRef, signer::address_of(sender))) {
            return (false, MODULE_ADMIN)
        };
        (true, *table::borrow_mut(&mut refProgram.userRef, signer::address_of(sender)))
    }
    public entry fun getRefCount<ADF>(sender: &signer) : u64 acquires RefProgram{
        
        assert!(exists<RefProgram<ADF>>(MODULE_ADMIN), ERROR_REF_PROGRAM_NOT_INIT);
        let refProgram = borrow_global_mut<RefProgram<ADF>>(MODULE_ADMIN);

        let referer = signer::address_of(sender);
        if(!table::contains(&mut refProgram.refMap, referer)) {
            return 0
        };

        let refs = *table::borrow_mut(&mut refProgram.refMap, referer);
        vector::length(&refs)
    }
    #[test_only]
    struct ADF {}
    #[test_only]
    use aptos_framework::managed_coin;
    #[test_only]
    use publisher::adf_util;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test (origin_account = @0xcaffee, acount2 = @0xcffff, aptos_framework = @aptos_framework)]
        public fun test_test(origin_account: signer, acount2 :signer) acquires RefProgram {
        create_account_for_test(signer::address_of(&origin_account));
        create_account_for_test(signer::address_of(&acount2));
        
        managed_coin::initialize<ADF>(
                &origin_account,
                b"ADF",
                b"ADF",
                8, false
            );

        adf_util::check_coin_store<ADF>(&origin_account);
        adf_util::check_coin_store<ADF>(&acount2);

        managed_coin::mint<ADF>(&origin_account, signer::address_of(&origin_account), MIN_ADX_OF_REFERER);

        createRefProgram<ADF>(&origin_account);
        regRef<ADF>(&acount2, signer::address_of(&origin_account));
        let (_, add) = getReferer<ADF>(&acount2);
        assert!(add == signer::address_of(&origin_account), 0);
        assert!(getRefCount<ADF>(&origin_account) == 1, 0);
    }
}