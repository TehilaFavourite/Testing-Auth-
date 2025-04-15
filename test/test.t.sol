// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console, stdError} from "forge-std/Test.sol";
import {AutheoRewardDistribution} from "../contracts/AutheoRewardDistribution.sol";

contract AuthTest is Test {
    AutheoRewardDistribution public autheoRewardDistribution;

    // setup is a function that is executed before each test
    function setUp() public {
        autheoRewardDistribution = new AutheoRewardDistribution(); //deploy a new AutheoRewardDistribution contract
    }

    //a passing test for setOwner

    // function testSetOwner() public {
    //     auth.setOwner(address(1));
    //     assertEq(auth.owner(), address(1));
    // }
}
