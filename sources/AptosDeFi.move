module publisher::adf_coin {
    use aptos_framework::coin::{Self};
    use std::signer;
    const MODULE_ADMIN: address = @publisher;

    struct ADF {}

    fun init_module(sender: &signer) {
        aptos_framework::managed_coin::initialize<ADF>(
            sender,
            b"Aptos DeFi",
            b"ADF",
            6,
            false,
        );
        coin::register<ADF>(sender);
        aptos_framework::managed_coin::mint<ADF>(sender, signer::address_of(sender), 1000000000000000);
    }

    public fun registerCoinStore(sender: &signer) {
        if(!coin::is_account_registered<ADF>(signer::address_of(sender))) {
            coin::register<ADF>(sender);
        };
    }
}
