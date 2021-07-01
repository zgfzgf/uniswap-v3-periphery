// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../libraries/TransferHelper.sol';
import '../interfaces/ISwapRouter.sol';

contract SwapExamples {
    //// For the scope of these swap examples, 
    //// we will detail the design considerations when using 
    //// `exactInput`, `exactInputSingle`, `exactOutput`, and  `exactOutputSingle`.

    //// It should be noted that for the sake of these examples, we purposefully pass in the swap router instead of inherit the swap router for simplicity.
    //// More advanced example contracts will detail how to inherit the swap router safely.

    ISwapRouter public immutable swapRouter;
    
    //// This example swaps DAI/WETH9 for single path swaps and DAI/USDC/WETH9 for multi path swaps.

    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    //// For this example, we will set the pool fee to 0.03%.
    uint24 constant poolFee = 3000;

    constructor(
        ISwapRouter _swapRouter
        
    ) {
        swapRouter = _swapRouter;
    }

    /// @notice swapInputSingle swaps DAI for WETH9 using the DAI/WETH9 0.03% pool by calling `exactInputSingle` in the swap router.
    /// @param amountIn The exact amount of DAI that will be swapped for WETH9.
    /// @return amountOut The amount of WETH9 received.
    function swapInputSingle(uint256 amountIn) external returns(uint256 amountOut) {

        //// Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransfer(DAI, address(this), amountIn);

        //// Approve the router to spend DAI.
        TransferHelper.safeApprove(DAI, address(swapRouter), amountIn);

        //// Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        //// We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: DAI, 
            tokenOut: WETH9,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 200,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        //// The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);

        //// Transfer `amountOut` of WETH9 to msg.sender.
        TransferHelper.safeTransferFrom(WETH9, address(this), msg.sender, amountOut);
    }

    /// @notice swapOutputSingle performs an exact output swap. 
    /// This still swaps DAI for WETH9 using the DAI/WETH9 0.03% pool, but instead of specifying how much DAI to swap, we specify how much WETH9 we want to receive.
    /// @param amountOut The exact amount of WETH9 to receive from the swap.
    /// @param amountInMaximum The amount of DAI we are willing to spend to receive the specified amount of WETH9.
    /// @return amountIn The amount of DAI actually spent in the swap.
    function swapOutputSingle(uint256 amountOut, uint256 amountInMaximum) external returns(uint256 amountIn) {
        
        //// Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransfer(DAI, address(this), amountInMaximum);

        //// Approve the router to spend the specifed `amountInMaximum` of DAI.
        //// In production, you should choose the maximum amount to spend based on oracles or other data sources to acheive a better swap.
        TransferHelper.safeApprove(DAI, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn:DAI,
            tokenOut:WETH9,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 200,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        //// Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);

        
        //// For exact output swaps, the amountInMaximum may not have all been spent. 
        //// If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(DAI, address(swapRouter), 0);
            TransferHelper.safeTransfer(DAI, msg.sender, amountInMaximum - amountIn);
        }

        //// Transfer amountOut of WETH9 to msg.sender to complete swap of DAI to WETH9.
        TransferHelper.safeTransferFrom(WETH9, address(this), msg.sender, amountOut);
    }

    /// @notice swapInputMultiplePools will execute a swap from DAI to WETH9, but use multiple pools instead of a single pool. For this example, we will swap DAI to USDC then USDC to WETH9 to acheive our desired output.
    /// @param amountIn The amount of DAI to be swapped.
    /// @return amountOut The amount of WETH9 received after the swap.
    function swapInputMultiplePools(uint256 amountIn) external returns (uint256 amountOut) {
        
        //// Transfer `amountIn` of DAI to this contract.
        TransferHelper.safeTransfer(DAI, address(this), amountIn);

        //// Approve the router to spend DAI.
        TransferHelper.safeApprove(DAI, address(swapRouter), amountIn);

        //// Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
        //// The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        //// Since we are swapping DAI to USDC and then USDC to WETH9 the path encoding is (DAI, 0.03%, USDC, 0.03%, WETH9).
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(DAI, poolFee, USDC, poolFee, WETH9),
            recipient: address(this),
            deadline: block.timestamp + 200,
            amountIn: amountIn,
            amountOutMinimum: 0

        });
        
        //// Executes the swap.
        amountOut = swapRouter.exactInput(params);

        //// Transfer `amountOut` of WETH9 to msg.sender.
        TransferHelper.safeTransferFrom(WETH9, address(this), msg.sender, amountOut);
    }

    /// @notice swapOutputMultiplePools is an exact output swap across multiple pools. 
    /// For this example, we still want to swap DAI for WETH9 through a USDC pool but we specify the desired amountOut of WETH9. Notice how the path encoding is slightly different in for exact output swaps.
    /// @param amountOut The desired amount of WETH9.
    /// @param amountInMaximum The maximum amount of DAI willing to be swapped for the specified amountOut of WETH9.
    /// @return amountIn The amountIn of DAI actually spent to receive the desired amountOut.
    function swapOutputMultiplePools(uint256 amountOut, uint256 amountInMaximum) external returns (uint256 amountIn) {

        //// Transfer the specified `amountInMaximum` to this contract.
        TransferHelper.safeTransfer(DAI, address(this), amountInMaximum);
        //// Approve the router to spend  `amountInMaximum`.
        TransferHelper.safeApprove(DAI, address(swapRouter), amountInMaximum);


        //// The parameter path is encoded as (tokenOut, fee, tokenIn/tokenOut, fee, tokenIn)
        //// The tokenIn/tokenOut field is the shared token between the two pools used in the multiple pool swap. In this case USDC is the "shared" token.
        //// For an exactOutput swap, the first swap that occurs is the swap which returns the eventual desired token. 
        //// In this case, our desired output token is WETH9 so that swap happpens first, and is encoded in the path accordingly.
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: abi.encodePacked(WETH9, poolFee, USDC, poolFee, DAI),
            recipient: address(this),
            deadline: block.timestamp + 200,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

        //// Executes the swap, returning the amountIn actually spent.
        amountIn = swapRouter.exactOutput(params);
        
        //// If the swap did not require the full amountInMaximum to achieve the exact amountOut then we refund msg.sender and approve the router to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(DAI, address(swapRouter), 0);
            TransferHelper.safeTransferFrom(DAI, address(this), msg.sender, amountInMaximum - amountIn);
        }

        //// Send the desired amountOut of WETH9 to msg.sender.
        TransferHelper.safeTransferFrom(WETH9, address(this), msg.sender, amountOut);

    }
}