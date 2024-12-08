// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {HackathonPrizeManagement} from "../src/HackathonManagement.sol";

contract HackathonPrizeManagementScript is Script {
    function run() external returns (HackathonPrizeManagement) {
        vm.startBroadcast();

        HackathonPrizeManagement hackathonPrizeManagement = new HackathonPrizeManagement();

        vm.stopBroadcast();
        return hackathonPrizeManagement;
    }
}
