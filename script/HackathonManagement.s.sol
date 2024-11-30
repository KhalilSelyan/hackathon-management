// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {HackathonPrizePool} from "../src/HackathonManagement.sol";

contract HackathonPrizePoolScript is Script {
    HackathonPrizePool public hackathonPrizePool;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        HackathonPrizePool hackathonPrizePool = new HackathonPrizePool();

        vm.stopBroadcast();
    }
}
