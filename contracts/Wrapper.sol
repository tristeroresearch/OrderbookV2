pragma solidity ^0.8.0;

contract TestBytes32ToAddress {
    function testBytes32ToAddress(bytes32 _bytes) external pure returns (address) {
        require(_bytes != bytes32(0), "Invalid address");
        return address(uint160(uint256(_bytes)));
    }
}