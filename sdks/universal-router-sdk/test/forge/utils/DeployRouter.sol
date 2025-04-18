// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniversalRouter} from "universal-router/interfaces/IUniversalRouter.sol";
import {UniversalRouter} from "universal-router/UniversalRouter.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {RouterParameters} from "universal-router/types/RouterParameters.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

contract DeployRouter is Test {
    using PoolIdLibrary for PoolKey;

    // These mainnet addresses are hardcoded to match the calldata generated by Hardhat
    // This ensures the correct addresses send and receive values as expected
    address public constant V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    bytes32 public constant PAIR_INIT_CODE_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    bytes32 public constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address internal constant RECIPIENT = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address internal constant FEE_RECIPIENT = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address internal constant MAINNET_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant MAINNET_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    // This is not the address of the position manager on mainnet
    // It’s the address where Foundry deploys PositionManager during the test
    // if this changes you need to update FORGE_V4_POSITION_MANAGER in addresses.ts
    address internal constant FORGE_POSM_ADDRESS = 0x2e234DAe75C793f67A35089C9d99245E1C58470b;

    ERC20 internal constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 internal constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 internal constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    uint256 ONE_USDC = 10 ** 6;
    uint256 ONE_DAI = 1 ether;

    IUniversalRouter public router;
    IPermit2 public permit2 = IPermit2(MAINNET_PERMIT2);
    IPoolManager public poolManager;
    PositionManager public v4PositionManager;

    address from;
    uint256 fromPrivateKey;
    string json;

    error InvalidTokenOrder();

    function deployRouter() public {
        UniversalRouter mockrouter = new UniversalRouter(
            RouterParameters({
                permit2: MAINNET_PERMIT2,
                weth9: WETH9,
                v2Factory: V2_FACTORY,
                v3Factory: V3_FACTORY,
                pairInitCodeHash: PAIR_INIT_CODE_HASH,
                poolInitCodeHash: POOL_INIT_CODE_HASH,
                v4PoolManager: address(poolManager),
                v3NFTPositionManager: V3_POSITION_MANAGER,
                v4PositionManager: address(v4PositionManager)
            })
        );

        vm.etch(MAINNET_ROUTER, address(mockrouter).code);
        router = IUniversalRouter(MAINNET_ROUTER);
    }

    ////////////////////////////////////////////////////////////////
    //////////////////////// V4 SETUP //////////////////////////////
    ////////////////////////////////////////////////////////////////

    function deployV4Contracts() public {
        poolManager = new PoolManager(address(this));
        v4PositionManager = new PositionManager(
            poolManager, IPermit2(MAINNET_PERMIT2), 100000, IPositionDescriptor(address(0)), IWETH9(WETH9)
        );
        vm.etch(FORGE_POSM_ADDRESS, address(v4PositionManager).code);
    }

    function initializeV4Pools() public {
        Currency eth = Currency.wrap(address(0));
        Currency weth = Currency.wrap(address(WETH));
        Currency usdc = Currency.wrap(address(USDC));
        Currency dai = Currency.wrap(address(DAI));

        uint256 amount = 10000 ether;

        deal(address(USDC), address(this), amount);
        USDC.approve(address(poolManager), amount);

        deal(address(WETH), address(this), amount);
        WETH.approve(address(poolManager), amount);

        deal(address(DAI), address(this), amount);
        DAI.approve(address(poolManager), amount);

        vm.deal(address(this), amount * 2);

        poolManager.unlock(
            abi.encode(
                [
                    PoolKey(eth, usdc, 3000, 60, IHooks(address(0))),
                    PoolKey(eth, dai, 3000, 60, IHooks(address(0))),
                    PoolKey(dai, usdc, 3000, 60, IHooks(address(0))),
                    PoolKey(usdc, weth, 3000, 60, IHooks(address(0)))
                ]
            )
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        PoolKey[4] memory poolKeys = abi.decode(data, (PoolKey[4]));

        for (uint256 i = 0; i < poolKeys.length; i++) {
            PoolKey memory poolKey = poolKeys[i];
            poolManager.initialize(poolKey, 79228162514264337593543950336);

            (BalanceDelta delta,) = poolManager.modifyLiquidity(
                poolKey,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 1000000 ether,
                    salt: 0
                }),
                bytes("")
            );

            _settle(poolKey.currency0, uint256((uint128(-delta.amount0()))));
            _settle(poolKey.currency1, uint256((uint128(-delta.amount1()))));
        }
    }

    function mintV3Position(address token0, address token1, uint24 fee, uint256 amount0Desired, uint256 amount1Desired)
        public
    {
        if (token0 >= token1) revert InvalidTokenOrder();

        deal(token0, from, 2 * amount0Desired);
        deal(token1, from, 2 * amount1Desired);

        vm.startPrank(from);
        ERC20(token0).approve(V3_POSITION_MANAGER, type(uint256).max);
        ERC20(token1).approve(V3_POSITION_MANAGER, type(uint256).max);

        INonfungiblePositionManager(V3_POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: 200040,
                tickUpper: 300000,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: from,
                deadline: type(uint256).max
            })
        );

        vm.stopPrank();
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}
