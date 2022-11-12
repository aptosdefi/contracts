
module publisher::adf_util {
    use std::signer;
    use aptos_framework::coin;

    
    public fun check_coin_store<X>(sender: &signer) {
        if (!coin::is_account_registered<X>(signer::address_of(sender))) {
            coin::register<X>(sender);
        };
    }
}