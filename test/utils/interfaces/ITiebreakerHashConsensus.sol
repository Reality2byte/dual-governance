// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ITiebreakerHashConsensus {
    function removeMembers(address[] memory members, uint256 quorum) external;
    function addMembers(address[] memory members, uint256 quorum) external;
    function getMembers() external view returns (address[] memory);
    function getQuorum() external view returns (uint256);
    function isMember(address member) external view returns (bool);
}
