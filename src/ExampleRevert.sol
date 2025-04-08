// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

error TestError();

contract revertWithError {
    function testRevert() public pure {
        if (false) {
            revert TestError();
        }
    }
}

contract revertWithString {
    function testRevert() public pure {
        if (false) {
            revert("Revert with string");
        }
    }
}

contract revertWithRequire {
    function testRevert() public pure {
        require(true, "Revert with require");
    }
}
