// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LumenPoolNotFound, LumenZeroAddress } from "../types/LumenErrors.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

struct PoolMetadata {
    bool listed;
    uint8 riskTier;
    uint256 listedAt;
    address token0;
    address token1;
    string label;
    string notesURI;
}

contract LumenPoolRegistry is Ownable2Step {
    mapping(address pool => PoolMetadata metadata) private _metadata;
    address[] private _listedPools;

    event PoolListed(
        address indexed pool,
        address indexed token0,
        address indexed token1,
        uint8 riskTier,
        string label
    );
    event PoolDelisted(address indexed pool);
    event PoolRiskTierUpdated(address indexed pool, uint8 riskTier);
    event PoolNotesUpdated(address indexed pool, string notesURI);

    constructor(
        address owner_
    ) Ownable2Step(owner_) { }

    function listPool(
        address pool,
        address token0,
        address token1,
        uint8 riskTier,
        string calldata label,
        string calldata notesURI
    ) external onlyOwner {
        if (pool == address(0) || token0 == address(0) || token1 == address(0)) {
            revert LumenZeroAddress();
        }
        PoolMetadata storage item = _metadata[pool];
        if (!item.listed) {
            _listedPools.push(pool);
            item.listedAt = block.timestamp;
        }
        item.listed = true;
        item.riskTier = riskTier;
        item.token0 = token0;
        item.token1 = token1;
        item.label = label;
        item.notesURI = notesURI;
        emit PoolListed(pool, token0, token1, riskTier, label);
    }

    function updateRiskTier(
        address pool,
        uint8 riskTier
    ) external onlyOwner {
        PoolMetadata storage item = _requireListed(pool);
        item.riskTier = riskTier;
        emit PoolRiskTierUpdated(pool, riskTier);
    }

    function updateNotesURI(
        address pool,
        string calldata notesURI
    ) external onlyOwner {
        PoolMetadata storage item = _requireListed(pool);
        item.notesURI = notesURI;
        emit PoolNotesUpdated(pool, notesURI);
    }

    function delistPool(
        address pool
    ) external onlyOwner {
        PoolMetadata storage item = _requireListed(pool);
        item.listed = false;
        emit PoolDelisted(pool);
    }

    function metadata(
        address pool
    ) external view returns (PoolMetadata memory) {
        return _metadata[pool];
    }

    function listedPoolAt(
        uint256 index
    ) external view returns (address) {
        return _listedPools[index];
    }

    function listedPoolsLength() external view returns (uint256) {
        return _listedPools.length;
    }

    function activePools() external view returns (address[] memory pools) {
        uint256 activeCount;
        for (uint256 i; i < _listedPools.length; ++i) {
            if (_metadata[_listedPools[i]].listed) activeCount++;
        }
        pools = new address[](activeCount);
        uint256 cursor;
        for (uint256 i; i < _listedPools.length; ++i) {
            address pool = _listedPools[i];
            if (_metadata[pool].listed) {
                pools[cursor] = pool;
                cursor++;
            }
        }
    }

    function poolsByRiskTier(
        uint8 riskTier
    ) external view returns (address[] memory pools) {
        uint256 count;
        for (uint256 i; i < _listedPools.length; ++i) {
            PoolMetadata memory item = _metadata[_listedPools[i]];
            if (item.listed && item.riskTier == riskTier) count++;
        }
        pools = new address[](count);
        uint256 cursor;
        for (uint256 i; i < _listedPools.length; ++i) {
            address pool = _listedPools[i];
            PoolMetadata memory item = _metadata[pool];
            if (item.listed && item.riskTier == riskTier) {
                pools[cursor] = pool;
                cursor++;
            }
        }
    }

    function _requireListed(
        address pool
    ) internal view returns (PoolMetadata storage metadata_) {
        metadata_ = _metadata[pool];
        if (!metadata_.listed) revert LumenPoolNotFound();
    }
}
